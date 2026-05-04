# StrictMode in the Demo App

The Android demo app at `android/app/` configures Android `StrictMode` so that
disk I/O on the main thread, leaked closables, registration leaks, and similar
issues introduced inside the GutenbergKit library surface during local
development. The demo crashes on any new `ThreadPolicy` violation, so library
regressions can't quietly slip in.

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
-   **`penaltyDeath()` on `ThreadPolicy`, but `penaltyLog()` on `VmPolicy`.** VM
    violations like `LeakedClosableObject` fire during GC and would crash at
    unpredictable times unrelated to the offending code path, which is
    unhelpful as a signal.
-   **`penaltyDialog()` is deliberately not enabled.** It interrupts manual
    testing without adding signal.
-   **No `StrictMode.allowThreadDiskReads()` permits inside the library.** That
    would hide the violation from host apps that also run StrictMode.

## Demo-side initialization shape

Because `penaltyDeath` crashes on any violation, the demo had to be
restructured so that nothing on the main thread touches disk:

-   **`AccountRepository`** is initialized lazily on `Dispatchers.IO` — its
    constructor reads `filesDir` and triggers `com.sun.jna.Native.<clinit>`,
    which itself runs ~8 disk reads while loading the dispatch library. See
    `GutenbergKitApplication.accountRepository()` and the `withAccountRepository`
    helper.
-   **All `AccountRepository` reads/writes** (`.all()`, `.store()`, `.remove()`)
    are wrapped in `withAccountRepository { ... }`, which awaits the deferred
    init and then dispatches the call to `Dispatchers.IO`. The Keystore-backed
    password transformer does both disk and crypto work per call.
-   **`EditorService.create`** touches `context.filesDir` / `context.cacheDir`,
    allocates a synchronous SSL context, and reads the asset bundles
    directory. `SitePreparationViewModel.createEditorService` wraps the call
    in `withContext(Dispatchers.IO)`.
-   **`EditorService.purge` / `EditorService.fetchAssetBundleCount`** also
    touch disk. Wrapped in `withContext(Dispatchers.IO)` at the call site.
-   **`EditorDependenciesSerializer.writeToDisk` / `readFromDisk`** are
    wrapped at the demo entry points: `SitePreparationActivity.launchEditor`
    (write before `startActivity`) and `EditorActivity.onCreate` (read into
    Compose state, render once ready).

`NetworkAvailabilityProvider` stays initialized eagerly on the main thread —
its constructor only stores a SAM lambda, no I/O.

## What's still in the library

Several violations originate inside `:Gutenberg`. The demo wraps the call sites
in `withContext(Dispatchers.IO)` rather than fixing them upstream — per
[#488](https://github.com/wordpress-mobile/GutenbergKit/issues/488), library
fixes are tracked separately and don't ship with the StrictMode work. Each is
a candidate for a follow-up that moves the I/O off the caller's thread or
exposes a `suspend` API:

-   `EditorService.create` (sync `EditorHTTPClient` + `Paths.cacheRoot` +
    `Paths.storageRoot` + `Paths.defaultTempStorageRoot` +
    `EditorURLCache.<init>` + `EditorAssetsLibrary.<init>`).
-   `EditorService.fetchAssetBundleCount` /
    `EditorAssetsLibrary.readAssetBundles`.
-   `EditorDependenciesSerializer.writeToDisk` /
    `EditorDependenciesSerializer.readFromDisk`.

## Reading violations

Filter logcat on tag `StrictMode`:

```bash
adb logcat -s StrictMode
```

Each violation prints a stack trace; the topmost app/library frame is the
actual call site. With `penaltyDeath` enabled, the violation also raises
`FATAL EXCEPTION: main` — `adb logcat -s AndroidRuntime` will show the crash.

## Verified flows

The following flows were exercised on a Pixel 9 (Android 16) and an Android
14 emulator with **zero** `ThreadPolicy` violations:

-   App cold launch.
-   Tap **Standalone editor** → **Prepare Editor** → **Start**.
-   Type into the editor.

The full demo flow listed in [#488](https://github.com/wordpress-mobile/GutenbergKit/issues/488)
(connected sites, native inserter sheet, photo permission paths, search,
overflow menu, backgrounding) wasn't exercised end-to-end. As new flows are
walked through and StrictMode flags new call sites, fix or wrap them at the
demo-app level rather than adding library-side permits.

## Adding new code

When introducing demo-app code that touches disk, network, or shared
resources:

1. Run the demo in debug mode.
2. Walk through the new code path end-to-end.
3. If the app crashes with `RuntimeException: StrictMode ThreadPolicy
   violation`, the offending call is in the stack trace — wrap it in
   `withContext(Dispatchers.IO)` (or move it into a coroutine).
4. **Never** suppress with `StrictMode.allowThreadDiskReads()` inside the
   library — that hides the violation from host apps.
