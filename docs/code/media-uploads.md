# Media Uploads

How a media upload gets from the editor to WordPress through native code: on iOS for every
editor with site credentials, on Android when the host supplies a `MediaProcessor` or
`MediaUploader`. See [Integration](../integration.md#media-handling) for the host-facing
API.

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
    Advertised whenever the site credentials are usable. With no processor or uploader,
    `InternalMediaClient` delivers the file.
-   **Android: `nativeUploadPort` and `nativeUploadToken`**, a loopback HTTP server
    (`HttpServer.kt`). Advertised only when the host supplies a handler.

With neither, requests pass through. On iOS the page's upload then goes through the REST
relay, which reads the whole file into memory, in the page and again in the app. That is
why iOS doesn't wait for a handler. On Android the page uploads straight to WordPress.

Measured in the Simulator (iOS 27.0) against wp-env, with the real editor and no handler:

| Upload | App peak, through the relay | App peak, over the scheme |
| ------ | --------------------------- | ------------------------- |
| 64 MB  | 234 MB                      | 54 MB                     |
| 128 MB | 426 MB                      | 54 MB                     |

The app started at 42 MB each time. Through the relay it grew by three times the file, and
still held 170 MB after the 64 MB upload ended.

### iOS: the `gbk-upload:` scheme

A `WKURLSchemeHandler` in the editor's own web view. It has no socket, so iOS can't reclaim
it when a suspended app's device idle-sleeps, which is what broke the loopback server
after an ordinary screen lock. It has no token either; see
[Who can use the schemes](#who-can-use-the-schemes).

WebKit hands a scheme handler only bodies it has buffered. Measured:

| `fetch` body                                                   | Reaches the handler                            | Measured on       |
| -------------------------------------------------------------- | ---------------------------------------------- | ----------------- |
| string, `URLSearchParams`, `ArrayBuffer`, text-only `FormData` | yes, as `httpBody`                             | device, Simulator |
| typed array, `DataView`                                        | yes, as `httpBody`                             | Simulator         |
| an in-memory `Blob`/`File`, or `FormData` holding one          | **no body at all**, and `fetch` still succeeds | device, Simulator |
| the same, made in another window (an iframe's)                 | **no body at all**, and `fetch` still succeeds | Simulator         |
| a `File` from the photo picker, in `FormData`                  | as `httpBodyStream`                            | device            |
| a dropped `File`, in `FormData`                                | **no body at all**                             | device            |
| `ReadableStream`                                               | never sent: `fetch` rejects                    | Simulator         |

The device was an iPhone 15 Pro on iOS 27 with Lockdown Mode on. The Simulator ran iOS 27.0
and iOS 17.5, each with Lockdown Mode off and with it forced on for the web view, and gave
the same results every way. No `OPTIONS` preflight reached the handler on any of them.

An object made in another window is not an `instanceof` this window's `Blob` or
`FormData`, so code that picks out the bodies to convert that way lets it through to be
dropped. The REST relay (`gbk-rest:`, `src/utils/fetch-relay.js`) meets the same rule for
every request it relays, and reads every body that is not a string into an `ArrayBuffer`.

`XMLHttpRequest` gets the same treatment from `src/utils/xhr-relay.js`, with three
differences measured in the iOS 27.0 Simulator:

-   A request whose `xhr.upload` was read before `send()`, as adding an upload listener
    does, has its body delivered as `httpBodyStream`, whatever the body. WebKit streams
    the body once that object exists, listener or not (`XMLHttpRequest.cpp` in WebKit).
    Otherwise, bodies arrive as they do from `fetch`. The relay reads either.
    A `Blob`, or `FormData` holding one, is dropped either way, so the page reads those
    into an `ArrayBuffer` first.
-   WebKit doesn't apply the request's `timeout`: one set to 500 ms was still waiting
    seconds later. The page sends it in an `X-GBK-Relay-Timeout` header, and native code
    fails the task with `URLError(.timedOut)`, which the page sees as a `timeout` event.
-   WebKit fires no upload `progress`, `load` or `loadend`. The page names each upload in
    an `X-GBK-Relay-Upload` header, which is never sent on. Native code reports how much of
    the body `URLSession` has sent, at most every 50 ms, and the page fires `progress` for
    each report. The report for the whole body always goes, and the page fires the last
    `progress`, `load` and `loadend` on it, or on the response's headers if they arrive
    first. As in the browser, the page fires none unless the caller read `xhr.upload`
    before `send()`. WebKit never sees the upload complete, so if the request fails
    afterwards it fires the upload's `abort`, `timeout` or `error` and a second
    `loadend`; the page stops those.

The streamed `fetch` case depends on where the file came from, and every failure is silent, so
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

-   **No fallback.** When native code refuses an upload, or can't be reached, that is the
    upload's error. The page's only other path is the REST relay, which holds the whole
    file in memory: on an iPhone SE (2nd gen), a 158 MB video sent that way got the web
    view killed. From `finish` on, a retry could also duplicate the attachment.
-   **Stopped tasks.** A task WebKit stops (the page aborted, or went away) is never
    answered — answering one raises — and its upload to WordPress is cancelled.
-   **Holding `finish`.** `finish` stays open while WordPress processes the upload. WebKit
    held one for 26 minutes in the foreground, and for hours across app suspension, and
    delivered the result.
-   **Disabled.** After `stopMediaHandling()` every request gets a `503`. An upload fails.
    A delete goes through the web view instead, and the REST relay sends it.

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

## Who can use the schemes

`gbk-upload:` and the REST relay's `gbk-rest:` don't check who is calling. A scheme
handler serves every frame in the editor's web view, not only the editor page, and native
code adds the site credential to what it sends to the site's REST API. So any frame can act
as the user through them.

The editor's frames fall into two groups:

| Frames                                                   | Origin       | Reads `window.GBKit` |
| -------------------------------------------------------- | ------------ | -------------------- |
| The editor page; embed previews                          | the editor's | yes                  |
| The Custom HTML preview; embeds from untrusted providers | `null`       | no                   |

Gutenberg's `SandBox` runs embed previews with `allowSameOrigin`. Core reduces an embed from
a provider it doesn't trust to a `sandbox="allow-scripts"` iframe.

The first group already has the credential through `GBKit.authHeader`, so the schemes give
it nothing new. The second group had no way to use the credential before the schemes, and
now it does. Measured on iOS 27.0 in the Simulator, with Lockdown Mode on and off: a
sandboxed `srcdoc` frame's `POST` through `gbk-rest:` reached the site with the credential,
and the frame read the reply.

A check on each request would shut out the second group:

-   **A token** in `GBKit`, sent as a header. A frame that can't read `GBKit` can't send it.
    WebKit sends a scheme handler no preflight, so the header costs nothing.
-   **An `Origin` check** that allows only what the editor page sends: no `Origin` with
    Lockdown Mode off, `file://` with it on. The second group's `fetch` says `null`. Loads
    that send no `Origin`, such as an image or a navigation, still get through, but they are
    `GET`s whose reply the frame can't read.

Neither check reaches the first group. Code at the editor's origin can call the editor's own
functions, so nothing on the request tells it apart from the editor. Its scripts come from
the providers core trusts with their embed HTML (`wp_filter_oembed_result`), and they have
the same reach in wp-admin.

Neither check is in place. It was left out of the scheme transports because it would close
the second group only, while the first stays as it was before the schemes.

The relay also sends requests for other hosts, so a plugin's call to its own service works
under Lockdown Mode. The page sends every request for another origin to one URL,
`gbk-rest://relay/fetch?url=…`, and native code decides how to send it. That gives every
frame a response from any `https` URL without CORS. Plain `http` goes only to the site's own
host — the API root's or the site URL's — on any port. Any other `http` request gets a `426`
before anything is sent. A device on the local network, or this device itself, can't present
a valid certificate for another host's name, so a name pointed at one fails before anything
is sent. A local host with a valid certificate for its own name is still reachable. A
redirect is followed only to an `http` or `https` URL, and never from `https` to `http`. A
URL with a user name or password is refused, as `fetch` refuses one: `URLSession` would store
it and send it on later requests to that host.

Native code adds the site credential only to a request for the site's REST API, to a URL it
builds from the configured root. It never removes or replaces an `Authorization` the page
sent, wherever the request goes, even when that is the site credential. Which hosts get the
site credential is the page's decision, made before the request reaches native code:
removing it there would protect nothing, because the page already holds the credential and
can send it anywhere. Without Lockdown Mode the editor page can already read those responses;
the second group couldn't.

## Background and timeouts

-   Uploads in flight share one `performExpiringActivity` assertion, which keeps the app
    running for about 30 seconds after it leaves the foreground. A longer upload is
    interrupted when iOS suspends the app.
-   The assertion is only ever taken in the foreground. iOS counts the 30 seconds once for
    the app, from when it left the foreground, so a later assertion buys nothing — and one
    taken after the time is up gets the app terminated instead of suspended (measured on
    iOS 27). An upload that begins in the background shares the assertion already held, or
    runs without one.
-   No part of an upload takes a thread of its own. The assertion is shared, and
    `MultipartBodyWriter` feeds each request's body from stream events, so an upload waiting
    for a connection costs a buffer and an open file. How many run at once is up to the
    network: in the Simulator, 400 started together peaked at 29 threads in the app.
-   A background `URLSession` would survive suspension. GutenbergKit doesn't use one: when
    WordPress was slow to answer, `nsurlsessiond` re-sent the whole upload about every 100
    seconds, and each copy became an attachment. A host `MediaUploader` that uses one has to
    dedupe.
-   Uploads get a 10-minute inactivity timeout (`EditorHTTPClient.uploadInactivityTimeout`).
    URLRequest's 60-second default fired while WordPress generated image sizes, and left
    the attachment behind.
-   Requests through the REST relay get the same 10-minute inactivity timeout. Without the
    relay, WebKit sends them, and on iOS it gives them no practical timeout (`INT_MAX`
    seconds per request). Against a server that never answered, the page's own `fetch` was
    still waiting after 11 minutes, where a 120-second limit on the relay had already
    answered `502`.

## Tests

-   JS: `src/utils/api-fetch-upload-scheme.test.js`, `api-fetch-post-process.test.js` (core's
    recovery over the scheme), `native-files.test.js`, and
    `api-fetch-upload-middleware.test.js` (the Android loopback transport).
-   Swift, on the host: `MediaUploadSchemeHandlerTests`, `MediaUploadSessionStoreTests`,
    `MediaUploadServiceTests`, `InternalMediaClientTests`, `BackgroundActivityTests`,
    `MediaFileSchemeHandlerTests`, `MediaImportTests`, `NativeFileInputTests`.
-   Swift, in the simulator: `EditorViewControllerMediaTeardownTests` runs the upload
    protocol in the editor's own `WKWebView`, and has a page's file input receive a file
    from `NativeFileInput`.
