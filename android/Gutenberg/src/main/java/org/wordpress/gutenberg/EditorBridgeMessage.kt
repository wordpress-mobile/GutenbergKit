package org.wordpress.gutenberg

import org.json.JSONObject

/**
 * A message the editor page posts to the native bridge, as
 * `{ "message": name, "body": { ... } }`: the same shape iOS receives.
 */
internal data class EditorBridgeMessage(val name: String, val body: JSONObject) {
    companion object {
        /**
         * Parses [json], or returns null when it isn't an object with a string
         * `message` and, if present, an object `body`. A missing body is empty.
         */
        fun parse(json: String): EditorBridgeMessage? {
            val message = runCatching { JSONObject(json) }.getOrNull() ?: return null
            val name = message.opt("message") as? String ?: return null
            val body = when (val rawBody = message.opt("body")) {
                null -> JSONObject()
                is JSONObject -> rawBody
                else -> return null
            }
            return EditorBridgeMessage(name, body)
        }
    }
}
