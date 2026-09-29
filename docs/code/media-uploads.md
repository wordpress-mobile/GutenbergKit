# Media Uploads

How a media upload gets from the editor to WordPress when the host supplies a
`MediaProcessor` or `MediaUploader`. See [Integration](../integration.md#media-handling)
for the host-facing API.

## Where uploads come from

| Source                                                       | Reaches native code as                                      |
| ------------------------------------------------------------ | ----------------------------------------------------------- |
| Upload button, drag-and-drop, paste, "upload external image" | a `File` in the page, sent by `nativeMediaUploadMiddleware` |
| The native block inserter (iOS)                              | a file on disk, which the page only references              |

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
an import of any size costs no memory. When the editor can upload natively it registers
the file with the scheme handler, and the page gets a stand-in `File`: a small JPEG preview
followed by a marker naming the session (`src/utils/native-upload-reference.js`). The marker
travels in the bytes because core re-creates the `File` when it builds `FormData`. The
middleware finishes the session instead of sending the stand-in, and never uploads a
stand-in through the web view. The page checks the real size against the site's
`maxUploadFileSize` itself, since the stand-in would pass core's check.

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
    recovery over the scheme), `native-upload-reference.test.js`, and
    `api-fetch-upload-middleware.test.js` (the Android loopback transport).
-   Swift, on the host: `MediaUploadSchemeHandlerTests`, `MediaUploadSessionStoreTests`,
    `MediaUploadServiceTests`, `InternalMediaClientTests`, `MediaFileSchemeHandlerTests`,
    `MediaImportTests`.
-   Swift, in the simulator: `EditorViewControllerMediaTeardownTests` runs the upload
    protocol in the editor's own `WKWebView`.
