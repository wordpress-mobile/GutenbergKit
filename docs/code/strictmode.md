# StrictMode in the Demo App

The Android demo app at `android/app/` configures Android `StrictMode` so that disk
I/O on the main thread, leaked closables, registration leaks, and similar
issues introduced inside the GutenbergKit library surface during local development.
This page documents the configuration, the violations the configured demo
currently surfaces, and the path to Phase 2 (`penaltyDeath`).

## Configuration

`GutenbergKitApplication.onCreate()` enables `StrictMode` in debug builds only
(`BuildConfig.DEBUG`). Release builds are unaffected.

```kotlin
StrictMode.setThreadPolicy(
    StrictMode.ThreadPolicy.Builder()
        .detectAll()
        .penaltyLog()
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

-   **`detectAll()` is intentional.** It's a superset that includes `detectDiskReads`,
    `detectDiskWrites`, `detectNetwork`, `detectCustomSlowCalls`,
    `detectResourceMismatches`, `detectUnbufferedIo`, and (on `VmPolicy`)
    `detectLeakedClosableObjects`, `detectLeakedRegistrationObjects`,
    `detectActivityLeaks`, `detectFileUriExposure`, `detectCleartextNetwork`,
    `detectContentUriWithoutPermission`, etc.
-   **`Application.onCreate()`** is the right place — earlier is better so the policy
    covers everything that follows.
-   **`penaltyDialog()` is deliberately not enabled.** It interrupts manual testing
    without adding signal.
-   **No `StrictMode.allowThreadDiskReads()` permits inside the library.** The
    demo-app-only configuration ensures host apps see the same violations the
    demo does.

## Reading violations

Filter logcat on tag `StrictMode`:

```bash
adb logcat -s StrictMode
```

Each violation prints a stack trace; the topmost app/library frame is the actual
call site.

## Currently catalogued violations

The catalogue below was captured by installing the debug build on an Android 14
emulator (Pixel API 34), launching the app, and tapping **Standalone editor**
(which routes through `SitePreparationActivity`).

### App launch — `Application.onCreate()`

10 `DiskReadViolation` lines. All originate from a single pair of statements in
`GutenbergKitApplication.onCreate()`:

1. **`filesDir.resolve("accounts")`** — 2 violations from
   `Context.getFilesDir()` checking and creating the app's data directory on
   first access.
2. **`AccountRepository(...)`** constructor — 8 violations from
   `com.sun.jna.Native.<clinit>` running `getTempDir()` /
   `removeTemporaryFiles()` while loading the JNA native dispatch library.
   Triggered transitively via `uniffi.wp_mobile.UniffiRustCallStatus.<init>` on
   first call.

**Status:** intentional-permit-because-startup. These are all one-time, occur
during process init before any user-visible UI is drawn, and originate from the
JVM/JNA loader rather than GutenbergKit code. Fixing means moving
`AccountRepository` initialization off the main thread, which is a demo-app
question rather than a library one.

### Site preparation — `SitePreparationViewModel.startLoading()`

Tapping any editor entry point lands on `SitePreparationActivity`, which kicks
off `SitePreparationViewModel.startLoading()`. This launches a coroutine on
`viewModelScope` (which defaults to `Dispatchers.Main.immediate`) that
synchronously constructs an `EditorService` and reads asset bundle counts. 10
violations:

1. **`EditorHTTPClient.<init>` (`EditorHTTPClient.kt:140`)** — 1
   `CustomViolation: newSSLContext`. SSLContext initialization on the main
   thread.
2. **`Paths.defaultCacheRoot` (`Paths.kt:58`)** — 2 `DiskReadViolation`s.
   `context.cacheDir` checks/creates the cache directory on first access.
3. **`Paths.defaultStorageRoot` (`Paths.kt:20`)** — 1 `DiskReadViolation`.
   `context.filesDir` (same pattern as above, on a different lazily-resolved
   directory).
4. **`Paths.defaultTempStorageRoot` (`Paths.kt:46`)** — 1 `DiskReadViolation`.
   Same pattern via `context.cacheDir`.
5. **`EditorURLCache.<init>` (`EditorURLCache.kt:37`)** — 1 `DiskReadViolation`.
   Cache directory existence check during construction.
6. **`EditorAssetsLibrary.<init>` (`EditorAssetsLibrary.kt:46`)** — 1
   `DiskReadViolation`. Asset bundle directory existence check during
   construction.
7. **`EditorService.create` (`EditorService.kt:117`)** — 2 `DiskReadViolation`s.
   Disk I/O during service construction.
8. **`EditorAssetsLibrary.readAssetBundles`
   (`EditorAssetsLibrary.kt:98`)** — 1 `DiskReadViolation`. Synchronous read of
   bundle directory contents.

**Status:** library bug, tracked for fix. `EditorService.create` and the
`Paths`/cache/asset library it constructs perform synchronous disk I/O. The
demo's `SitePreparationViewModel.countAssetBundles` runs them on
`viewModelScope` without an explicit dispatcher, so they execute on
`Dispatchers.Main.immediate`. Either:

-   the demo should wrap the call in `withContext(Dispatchers.IO) { ... }`, or
-   `EditorService.create` should accept a `CoroutineDispatcher` and do the
    disk-touching work on it itself (preferred — host apps shouldn't have to
    know).

These are real library-side issues that Phase 2 (`penaltyDeath`) cannot ship
until they're resolved. Out of scope for this PR per the issue (#488).

### Editor flow

The full editor flow (loading the editor, opening the inserter sheet, picking
photos, etc.) requires network-loaded asset bundles and was not exercised when
this catalogue was written. The catalogue should be expanded as those flows are
exercised manually — see "Adding to this catalogue" below.

## Adding to this catalogue

When introducing a feature that touches disk, network, or shared resources:

1. Run the demo in debug mode on a connected device or emulator.
2. Filter logcat on `StrictMode`.
3. Walk through every code path the feature touches.
4. For each new violation:
    - If it's a library bug, file a follow-up issue and link it here.
    - If it's an intentional, sub-millisecond, one-time-per-process cost
      (e.g. a `SharedPreferences` warm-up), document it here as
      *intentional-permit-because-X*.
    - **Never** suppress with `StrictMode.allowThreadDiskReads()` inside the
      library — that hides the violation from host apps.

## Phase 2 — `penaltyDeath()`

Once the library-side violations above have been fixed, the demo will switch
its thread policy to:

```kotlin
.penaltyDeath()
```

Phase 2 is a separate PR. It crashes the demo on any new violation, ensuring
future library changes can't quietly regress.

`VmPolicy` will remain on `penaltyLog()` even after Phase 2 — VM violations
like `LeakedClosableObject` happen during GC and crash the app at unpredictable
times unrelated to the offending code path, which is unhelpful as a signal.
