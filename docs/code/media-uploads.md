# Media Uploads

How a media upload gets from the editor to WordPress when the host supplies a
`MediaProcessor` or `MediaUploader`. See [Integration](../integration.md#media-handling)
for the host-facing API.

## Where uploads come from

| Source                                                       | Reaches native code as                                      |
| ------------------------------------------------------------ | ----------------------------------------------------------- |
| Upload button, drag-and-drop, paste, "upload external image" | a `File` in the page, sent by `nativeMediaUploadMiddleware` |
| The native block inserter (iOS)                              | a `File` native code hands the page, sent the same way      |

Both end in the same place. Core's `mediaUpload` builds a `FormData` and calls
`apiFetch({ path: '/wp/v2/media', method: 'POST' })`. `nativeMediaUploadMiddleware`
(`src/utils/api-fetch.js`) intercepts that and hands the upload to native code. Native code
returns WordPress's response, and core finishes the job: it replaces the placeholder,
releases the save lock, and shows errors.

Core's own upload middleware sits above ours and always asks for `parse: false`. It reads
`x-wp-upload-attachment-id` off a failed response to retry `post-process`, so native code
relays that header, and every native response exposes it under CORS. The orphan `DELETE`
core sends when recovery fails is relayed natively too: a cross-origin editor can't send it
itself.

## Transports

The middleware picks one from what the host advertises in `GBKit`:

-   **iOS: `nativeUploadScheme`** (`gbk-upload`), served by `MediaUploadSchemeHandler`.
-   **Android: `nativeUploadPort` and `nativeUploadToken`**, a loopback HTTP server
    (`HttpServer.kt`).

With neither, requests pass through and the page uploads straight to WordPress.

### iOS: the `gbk-upload:` scheme

A `WKURLSchemeHandler` in the editor's own web view. It has no socket, so iOS can't reclaim
it when a suspended app's device idle-sleeps, which is what broke the loopback server
after an ordinary screen lock. There is no token either: only this web view can load the
scheme.

WebKit hands a scheme handler only bodies it has buffered. Measured on iOS 27 with
Lockdown Mode:

| `fetch` body                                          | Reaches the handler                            |
| ----------------------------------------------------- | ---------------------------------------------- |
| string, `URLSearchParams`, `ArrayBuffer`              | yes, as `httpBody`                             |
| an in-memory `Blob`/`File`, or `FormData` holding one | **no body at all**, and `fetch` still succeeds |
| a `File` from the photo picker, in `FormData`         | as `httpBodyStream`                            |
| a dropped `File`, in `FormData`                       | **no body at all**                             |

The streamed case depends on where the file came from, and every failure is silent, so
the page always sends the file as 4 MB `ArrayBuffer` chunks:

| Request                                | Body                         | Response             |
| -------------------------------------- | ---------------------------- | -------------------- |
| `POST gbk-upload://upload/sessions`    | `{filename, mimeType, size}` | `201 {"id"}`         |
| `POST …/sessions/<id>/chunks?offset=N` | the chunk                    | `200 {"received"}`   |
| `POST …/sessions/<id>/finish`          | `{fields, query}`            | WordPress's response |
| `POST …/sessions/<id>/cancel`          | —                            | `204`                |
| `POST …/media/<attachmentId>/delete`   | `{query}`                    | WordPress's response |

`MediaUploadSessionStore` writes each chunk straight to a staging file and refuses one at
the wrong offset. A 1.1 GB upload peaked at 44 MB of app memory.

-   **Fallback.** A failure before `finish` means WordPress never saw the file, so the page
    uploads through the web view instead. From `finish` on it doesn't retry: native code
    may already have sent the file.
-   **Stopped tasks.** A task WebKit stops (the page aborted, or went away) is never
    answered — answering one raises — and its upload to WordPress is cancelled.
-   **Holding `finish`.** `finish` stays open while WordPress processes the upload. WebKit
    held one for 26 minutes in the foreground, and for hours across app suspension, and
    delivered the result.
-   **Disabled.** After `stopMediaHandling()` every request gets a `503`, which the page
    takes as the cue to fall back.

### Native inserter media

The inserter imports a picked photo or video as a file. On APFS that copy is a clone, so
an import of any size costs no memory. The page then needs it as a `File`: Gutenberg's
upload pipeline reads the bytes from one, and so does a block that uploads on its own
(VideoPress sends its file to its own endpoint and never calls `mediaUpload`).

The page clicks a hidden file input (`requestNativeFiles` in `src/utils/native-files.js`),
and `NativeFileInput` answers the open panel WebKit would otherwise show with the imported
files. The page gets what the system picker gives it: `File`s that WebKit reads from disk
as they are sliced. From there an inserter pick is an Upload-button pick. On an iPhone 14
Pro (iOS 18.6.2) the page read a 1.1 GB video through 4 MB slices in about a second,
byte for byte.

-   **iOS 18.4.** WebKit asks its UI delegate for the panel from iOS 18.4. Before that the
    inserter hides the photo library and the camera, and media is added from a block's own
    upload button.
-   **Only while offering.** A UI delegate that implements the panel answers every file
    input, so `NativeFileInput` is the web view's UI delegate only for the insertion, and
    puts the host's delegate back.
-   **User activation.** The click needs the user activation the native script call
    carries, so the page asks for the files before its first `await`.
-   **Fallback.** If the files don't arrive, the page fetches them from `gbk-media-file:`
    instead, which holds each file in the page's memory.
-   **WebKit's copies.** WebKit copies every file a file input receives into
    `tmp/WKFileUploadPanel-…` (a clone) and never deletes it. `MediaFileManager` removes
    the ones older than two days, along with its own imports.

## Background and timeouts

-   An upload holds a `performExpiringActivity` assertion, which keeps the app running for
    about 30 seconds after it leaves the foreground. A longer upload is interrupted when iOS
    suspends the app.
-   A background `URLSession` would survive suspension. GutenbergKit doesn't use one: when
    WordPress was slow to answer, `nsurlsessiond` re-sent the whole upload about every 100
    seconds, and each copy became an attachment. A host `MediaUploader` that uses one has to
    dedupe.
-   Uploads get a 10-minute inactivity timeout (`EditorHTTPClient.uploadInactivityTimeout`).
    URLRequest's 60-second default fired while WordPress generated image sizes, and left
    the attachment behind.

## Tests

-   JS: `src/utils/api-fetch-upload-scheme.test.js`, `api-fetch-post-process.test.js` (core's
    recovery over the scheme), `native-files.test.js`, and
    `api-fetch-upload-middleware.test.js` (the Android loopback transport).
-   Swift, on the host: `MediaUploadSchemeHandlerTests`, `MediaUploadSessionStoreTests`,
    `MediaUploadServiceTests`, `InternalMediaClientTests`, `MediaFileSchemeHandlerTests`,
    `MediaImportTests`, `NativeFileInputTests`.
-   Swift, in the simulator: `EditorViewControllerMediaTeardownTests` runs the upload
    protocol in the editor's own `WKWebView`, and has a page's file input receive a file
    from `NativeFileInput`.
