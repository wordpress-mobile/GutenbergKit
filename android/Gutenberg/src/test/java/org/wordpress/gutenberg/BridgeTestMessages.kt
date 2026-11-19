package org.wordpress.gutenberg

import org.json.JSONObject

/** Delivers the bridge message [name], with [fields] as its body, as the editor page posts it. */
internal fun GutenbergView.postBridgeMessage(name: String, vararg fields: Pair<String, Any>) {
    val body = JSONObject()
    fields.forEach { (key, value) -> body.put(key, value) }
    receiveBridgeMessage(JSONObject().put("message", name).put("body", body).toString())
}
