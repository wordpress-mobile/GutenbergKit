package org.wordpress.gutenberg

import android.os.Looper
import org.json.JSONObject
import org.robolectric.Shadows.shadowOf

/**
 * Delivers the bridge message [name], with [fields] as its body, as the editor page
 * posts it from the main frame. Returns the replies native code sent.
 */
internal fun GutenbergView.postBridgeMessage(name: String, vararg fields: Pair<String, Any>): List<String> {
    val body = JSONObject()
    fields.forEach { (key, value) -> body.put(key, value) }
    return postBridgeMessageJson(JSONObject().put("message", name).put("body", body).toString())
}

/**
 * Delivers [json] to the bridge as a page posts it, by default the editor page in
 * the main frame, and runs the main looper so it's handled. Returns the replies
 * native code sent.
 */
internal fun GutenbergView.postBridgeMessageJson(
    json: String,
    sourceOrigin: String = checkNotNull(editorOrigin) { "The editor hasn't loaded" },
    isMainFrame: Boolean = true
): List<String> {
    val replies = mutableListOf<String>()
    receiveBridgeMessage(json, sourceOrigin, isMainFrame) { replies += it }
    shadowOf(Looper.getMainLooper()).idle()
    return replies
}
