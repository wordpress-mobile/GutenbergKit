# Authorization Header Scope

## Overview

The host app hands GutenbergKit a site's credentials as `authHeader`. The editor makes requests to more places than the site: it downloads plugin and theme assets from whichever hosts the site names, and a block can call another party's service through `apiFetch( { url } )`. Those hosts have no business receiving the site's credentials.

GutenbergKit therefore sends the `Authorization` header only to requests within the site's **authorization scope**. The same rule is implemented once on each platform, and all three implementations must agree.

## The Rule

A request carries the `Authorization` header when either of these holds:

1. **It is for the site or its API.** The request's origin — scheme, host, and port — is the origin of `siteURL` or of `siteApiRoot`. This always applies, so an app that names nothing else keeps working.
2. **The app named its host.** The request is over HTTPS and its host matches an entry in `authHeaderDomains`.

Every other request goes out without the header.

Because the first case compares origins, a lookalike host (`https://example.com.vendor.net`), another port, and the site's own host over `http` when the site is `https` are all outside the scope.

## Naming Other Hosts

`authHeaderDomains` is empty by default. Each entry is taken exactly as written:

| Entry       | Matches                                               |
| ----------- | ----------------------------------------------------- |
| `s0.wp.com` | `s0.wp.com` only — not its subdomains, not `wp.com`   |
| `*.wp.com`  | `wp.com` and every subdomain of it, at any depth      |
| `*.com`     | Every `.com` host — a wildcard is not checked further |

GutenbergKit does not judge what a wildcard covers: no public-suffix check, no minimum number of labels. Name the narrowest domain that will do.

Entries are trimmed and lowercased, and may end with the trailing dot of a fully qualified name. A named entry matches its host on any port, over HTTPS only. An entry is ignored when it is empty, or when it has a `*` anywhere but as the whole first label (`.wp.com`, `s*.wp.com`, `*.*.com`).

**Swift**

```swift
let configuration = EditorConfigurationBuilder(
    postType: "post",
    siteURL: URL(string: "https://example.wordpress.com")!,
    siteApiRoot: URL(string: "https://public-api.wordpress.com/")!
)
    .setAuthHeader("Bearer your-token")
    .setAuthHeaderDomains(["*.wp.com", "*.files.wordpress.com"])
    .build()
```

**Kotlin**

```kotlin
val configuration = EditorConfiguration.builder(
    siteURL = "https://example.wordpress.com",
    siteApiRoot = "https://public-api.wordpress.com/"
)
    .setAuthHeader("Bearer your-token")
    .setAuthHeaderDomains(setOf("*.wp.com", "*.files.wordpress.com"))
    .build()
```

### WordPress.com

GutenbergKit infers nothing about WordPress.com: no `wp.com` or `wordpress.com` host is built into the library. A site reached through WordPress.com is served from more than its own address — its assets from `wp.com`, its files from `files.wordpress.com` — so the app names them, as above. Both demo apps do this for WordPress.com accounts and name nothing for self-hosted sites, where an application password is good for the one site.

### Custom Editor Assets Endpoint

`editorAssetsEndpoint` is subject to the same rule. An endpoint on a host other than the site's or its API's is fetched without credentials unless that host is named in `authHeaderDomains`.

## Where It Is Enforced

| Platform | Rule                                                               | Applied by                                                                                                                             |
| -------- | ------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| iOS      | `EditorAuthorizationScope`                                         | `EditorHTTPClient`, for REST requests, asset downloads, and media uploads                                                              |
| Android  | `EditorAuthorizationScope`                                         | `EditorHTTPClient.perform` and `download`, and the manifest request of the `EditorAssetsLibrary` in the `org.wordpress.gutenberg` root |
| Web      | `isWithinAuthorizationScope` in `src/utils/authorization-scope.js` | `tokenAuthMiddleware` in `src/utils/api-fetch.js`                                                                                      |

`GBKitGlobal` carries `authHeaderDomains` to the web editor, so it applies the list the native side was configured with.

On the web side, a request made by `path` is for the site's API — the root URL middleware joins the path to `siteApiRoot` — and always carries the header. A request made by `url` alone is checked against the scope. `credentials: 'omit'` is set only when the header is attached.

jQuery AJAX requests are scoped separately, in `src/utils/ajax.js`, to the origin of `siteURL`. They do not consult `authHeaderDomains`.

Android's native media upload relay (`DefaultMediaUploader`) builds its URL from `siteApiRoot`, so it is within the scope by construction.

### Constructing a Client

Both native `EditorHTTPClient` constructors require the scope. Derive it from the configuration rather than assembling it by hand:

**Swift**

```swift
let client = EditorHTTPClient(configuration: configuration)
```

**Kotlin**

```kotlin
val client = EditorHTTPClient(
    authHeader = configuration.authHeader,
    authorizationScope = EditorAuthorizationScope(configuration)
)
```

## Limits

-   **A host-supplied HTTP client is not covered.** An app's own `EditorHTTPClientProtocol` implementation adds whichever headers it likes, to whichever requests it likes.
-   **Requests the web view makes itself never carry the header.** Images, scripts, and stylesheets loaded by the document are outside `apiFetch` and the native clients. Naming `*.files.wordpress.com` makes those hosts eligible for requests GutenbergKit makes; it does not by itself make a private site's media display.
-   **The scope is decided from the request's URL.** Where a redirect then leads, and which headers follow it there, is up to the platform's HTTP stack.
