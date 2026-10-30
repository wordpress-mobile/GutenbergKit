# StrictMode in the Demo App

The Android demo app at `android/app/` configures Android `StrictMode` so that
disk I/O on the main thread, leaked closables, registration leaks, and similar
issues introduced inside the GutenbergKit library surface during local
development.

`ThreadPolicy` violations **crash the demo**, so new main-thread disk or network
work fails loudly during development. `VmPolicy` violations are logged only.

## Configuration

`GutenbergKitApplication.onCreate()` enables `StrictMode` in debug builds only
(`BuildConfig.DEBUG`). Release builds are unaffected.

```kotlin
StrictMode.setThreadPolicy(
    StrictMode.ThreadPolicy.Builder()
        .detectAll()
        .penaltyLog()
        .penaltyDeath()
        .build()
)
StrictMode.setVmPolicy(
    StrictMode.VmPolicy.Builder()
        .detectAll()
        .penaltyLog()
        .build()
)
```

Configuration notes:

-   **`detectAll()` is intentional.** It's a superset that includes
    `detectDiskReads`, `detectDiskWrites`, `detectNetwork`,
    `detectCustomSlowCalls`, `detectResourceMismatches`, `detectUnbufferedIo`,
    and (on `VmPolicy`) `detectLeakedClosableObjects`,
    `detectLeakedRegistrationObjects`, `detectActivityLeaks`,
    `detectFileUriExposure`, `detectCleartextNetwork`, etc.
-   **`Application.onCreate()`** is the right place — earlier is better so the
    policy covers everything that follows.
-   **`ThreadPolicy` keeps `penaltyLog()` alongside `penaltyDeath()`.** The log
    prints the full violation before the crash.
-   **`VmPolicy` stays on `penaltyLog()`.** VM violations like
    `LeakedClosableObject` fire during GC and would crash at unpredictable
    times unrelated to the offending code path, which is unhelpful as a signal.
-   **`penaltyDialog()` is deliberately not enabled.** It interrupts manual
    testing without adding signal.
-   **No `StrictMode.allowThreadDiskReads()` permits inside the library.** That
    would hide the violation from host apps that also run StrictMode.

## Demo-side initialization shape

The demo keeps its own code off the main thread's disk, so the log only shows
violations that come from the library:

-   **`AccountRepository`** is initialized lazily on `Dispatchers.IO` — its
    constructor reads `filesDir` and triggers `com.sun.jna.Native.<clinit>`,
    which itself runs ~8 disk reads while loading the dispatch library. See
    `GutenbergKitApplication.accountRepository()` and the `withAccountRepository`
    helper.
-   **All `AccountRepository` access** (`.all()`, `.get()`, `.store()`,
    `.remove()`, and `GutenbergKitApplication.findAccount`) goes through
    `withAccountRepository { ... }`, which awaits the deferred init and then
    dispatches the call to `Dispatchers.IO`. The Keystore-backed password
    transformer does both disk and crypto work per call. This includes signing
    in from the `accounts` launch extra (`make login-android-app`).
-   **`GutenbergKitApplication.createApiClient`** suspends and builds the
    `WpRequestExecutor` on `Dispatchers.IO`. Its OkHttp client sets up an SSL
    context, which StrictMode reports as a slow call.
-   **`EditorService.create`** touches `context.filesDir` / `context.cacheDir`,
    allocates a synchronous SSL context, and reads the asset bundles
    directory. `SitePreparationViewModel.createEditorService` wraps the call
    in `withContext(Dispatchers.IO)`.
-   **`EditorService.prepare`, `purge` and `fetchAssetBundleCount`** also touch
    disk (`prepare` runs a periodic asset cleanup on the caller's thread).
    Wrapped in `withContext(Dispatchers.IO)` at the call site.
-   **`EditorDependenciesSerializer.writeToDisk` / `readFromDisk`** are
    wrapped at the demo entry points: `SitePreparationActivity.launchEditor`
    and `launchPostsList` (write before `startActivity`) and
    `EditorActivity.onCreate` (read into Compose state, render once ready).

`NetworkAvailabilityProvider` stays initialized eagerly on the main thread —
its constructor only stores a SAM lambda, no I/O.

## What's still in the library

### Wrapped by the demo

These library calls do I/O on the caller's thread. The demo calls them on
`Dispatchers.IO`, but every host has to know to do the same. Each is a
candidate for a follow-up that moves the I/O off the caller's thread or
exposes a `suspend` API:

-   `EditorService.create` (sync `EditorHTTPClient` + `Paths.cacheRoot` +
    `Paths.storageRoot` + `Paths.defaultTempStorageRoot` +
    `EditorURLCache.<init>` + `EditorAssetsLibrary.<init>`).
-   `EditorService.prepare` → `EditorService.cleanup` →
    `EditorAssetsLibrary.readAssetBundles`.
-   `EditorService.fetchAssetBundleCount` /
    `EditorAssetsLibrary.readAssetBundles`.
-   `EditorDependenciesSerializer.writeToDisk` /
    `EditorDependenciesSerializer.readFromDisk`.

### Editor load

`GutenbergView` starts the upload server and builds the editor globals on
`Dispatchers.IO` before it loads the editor page. When the host passes no
prepared dependencies, it also creates and prepares its `EditorService` there.
Opening the editor does no disk or SSL work on the main thread
([#848](https://github.com/wordpress-mobile/GutenbergKit/issues/848)).

### Expected `VmPolicy` noise

-   `UntaggedSocketViolation` — logged for most network requests (WebView,
    OkHttp, wordpress-rs). The sockets aren't tagged with
    `TrafficStats.setThreadStatsTag()`. Harmless; ignore it.

## Reading violations

Filter logcat on tag `StrictMode`:

```bash
adb logcat -s StrictMode
```

Each violation prints a stack trace; the topmost app/library frame is the
actual call site.

## Verified flows

Exercised on an API 36 emulator, with only the `VmPolicy` noise listed above:

-   App cold launch, including signing in with `make login-android-app`.
-   **Standalone editor** → **Prepare Editor** → **Start**, then type.
-   A connected site → **Prepare Editor** → **Browse** → open a post, then type.
-   A connected site → **Browse** → open a post, without preparing first.
-   A connected site → **Start**, with and without **Prepare Editor**, and with
    **Enable Native Media Upload** on and off.
-   Native inserter sheet: category tabs and search.
-   Background the app, then resume it.

Not yet walked: **Save** (writes to the site), the inserter's media strip and
its photo permission prompts, and the camera tile.

## Adding new code

When introducing demo-app code that touches disk, network, or shared
resources:

1. Run the demo in debug mode.
2. Walk through the new code path end-to-end with `adb logcat -s StrictMode`
   open.
3. If the demo crashes with a `ThreadPolicy` violation, the offending call is
   in the stack trace — wrap it in `withContext(Dispatchers.IO)` (or move it
   into a coroutine).
4. **Never** suppress with `StrictMode.allowThreadDiskReads()` inside the
   library — that hides the violation from host apps.
