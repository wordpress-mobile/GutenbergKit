# StrictMode in the Demo App

The Android demo app at `android/app/` configures Android `StrictMode` so that
disk I/O on the main thread, leaked closables, registration leaks, and similar
issues introduced inside the GutenbergKit library surface during local
development.

For now, violations are **logged, not fatal**. The library still reads the disk
on the main thread while the editor page loads, so crashing on violations would
crash every editor launch.
[#848](https://github.com/wordpress-mobile/GutenbergKit/issues/848) lists those
violations and tracks switching `ThreadPolicy` to `penaltyDeath()`.

Some other library calls do disk or SSL work on the caller's thread, so the demo
makes them on `Dispatchers.IO`.
[#869](https://github.com/wordpress-mobile/GutenbergKit/issues/869) lists them.

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

-   **`detectAll()` is intentional.** It's a superset that includes
    `detectDiskReads`, `detectDiskWrites`, `detectNetwork`,
    `detectCustomSlowCalls`, `detectResourceMismatches`, `detectUnbufferedIo`,
    and (on `VmPolicy`) `detectLeakedClosableObjects`,
    `detectLeakedRegistrationObjects`, `detectActivityLeaks`,
    `detectFileUriExposure`, `detectCleartextNetwork`, etc.
-   **`Application.onCreate()`** is the right place — earlier is better so the
    policy covers everything that follows.
-   **`VmPolicy` stays on `penaltyLog()`, even after #848.** VM violations like
    `LeakedClosableObject` fire during GC and would crash at unpredictable
    times unrelated to the offending code path, which is unhelpful as a signal.
-   **`penaltyDialog()` is deliberately not enabled.** It interrupts manual
    testing without adding signal.
-   **No `StrictMode.allowThreadDiskReads()` permits inside the library.** That
    would hide the violation from host apps that also run StrictMode.

## Expected `VmPolicy` noise

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

## Adding new code

When introducing demo-app code that touches disk, network, or shared
resources:

1. Run the demo in debug mode.
2. Walk through the new code path end-to-end with `adb logcat -s StrictMode`
   open.
3. If a new `ThreadPolicy` violation shows up, the offending call is in the
   stack trace — wrap it in `withContext(Dispatchers.IO)` (or move it into a
   coroutine).
4. **Never** suppress with `StrictMode.allowThreadDiskReads()` inside the
   library — that hides the violation from host apps.
