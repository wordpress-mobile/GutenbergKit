package org.wordpress.gutenberg

import android.net.Uri

/**
 * Whether the editor configuration can reach the configured site for media, and the
 * fail-fast that enforces it.
 *
 * The counterpart of iOS's `MediaServerCredentials`, kept deliberately close to it.
 * This is a *crash* policy, and it has already diverged silently between the platforms
 * once: iOS required an absolute site root while this side checked only `isEmpty()`, so
 * a scheme-less root trapped on iOS and started a server whose every delete failed on
 * Android. Both platforms keep the policy in a type of this name so the two can be
 * diffed against each other rather than hunted for across view code.
 */
internal object MediaServerCredentials {
    /**
     * Whether an [InternalMediaClient] built from this configuration could actually
     * reach the site.
     *
     * Both fields are required. The client delivers GutenbergKit's uploads to the
     * configured site, so it needs somewhere to send them and credentials to be
     * accepted; with either missing, every media request it makes fails.
     *
     * "Somewhere to send them" means an *absolute* root, not merely a non-empty one.
     * OkHttp rejects a scheme-less URL from `Request.Builder.url` with
     * `IllegalArgumentException`, which is not an `IOException` — so it escapes
     * [MediaUploadServer]'s delete handler and degrades to a generic 500 the editor
     * cannot parse into an error, and the orphan cleanup that delete exists for fails
     * silently. An empty root parses to the same nulls, so this still rejects
     * everything the older `isEmpty()` check did.
     *
     * Emptiness is tested as well as nullity because `Uri` and Swift's `URL` disagree
     * on how they report a missing authority: `file:///tmp/wp-json` yields a `null`
     * host on iOS but an *empty* one here. Treating both as absent is what keeps the
     * two predicates answering alike.
     */
    fun areUsable(siteApiRoot: String, authHeader: String): Boolean {
        if (authHeader.isEmpty()) return false
        val uri = Uri.parse(siteApiRoot)
        return !uri.scheme.isNullOrEmpty() && !uri.host.isNullOrEmpty()
    }

    /**
     * Throws if the host supplied a [MediaUploader] without usable credentials.
     *
     * The behavior forks by intent:
     *
     * - A [MediaProcessor] only enhances GutenbergKit-owned uploads. With no
     *   credentials there is nothing to deliver through, so nothing to process — the
     *   server simply stays down and uploads fall to the default WebView path. That is
     *   [areUsable]'s job, at the point the server would start.
     *
     * - A [MediaUploader] means the host is *taking over* uploads, and falling back
     *   would drop that whole stack — its queueing, its retries — while media appeared
     *   to keep working. Worth failing over rather than logging.
     *
     * What makes it a *failure* rather than a warning is that the configuration is
     * incoherent, not merely unlucky: an uploader's media deletes still relay through
     * the internal media client, so there is no site root and auth header under which
     * this host's uploader could have worked. Contrast the conditions the host's
     * environment imposes at server start — the network policy that blocks cleartext to
     * localhost, a port that won't bind — which log and degrade, because the very same
     * configuration works once the environment allows it. Dropping the uploader is the
     * symptom both share; only this one has a cause the host can fix in the
     * configuration it just handed over.
     *
     * Called from [GutenbergView.mediaUploader]'s setter, not from the server start —
     * the earliest point available here, since this platform takes its media handlers
     * as mutable properties rather than at construction. Checking where the host hands
     * the uploader over puts the caller's own line in the stack trace, instead of
     * surfacing the mistake later from inside a page-load callback. (iOS checks in
     * `EditorViewController.init`, for the same reason.)
     */
    fun requireCredentialsForUploader(siteApiRoot: String, authHeader: String, hasUploader: Boolean) {
        if (!hasUploader) return
        check(areUsable(siteApiRoot, authHeader)) {
            "A mediaUploader needs site credentials so GutenbergKit can relay the " +
                "editor's media deletes to the configured site. Set an absolute " +
                "siteApiRoot and the auth header in the editor configuration."
        }
    }
}
