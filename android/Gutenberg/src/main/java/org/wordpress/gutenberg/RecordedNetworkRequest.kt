package org.wordpress.gutenberg

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.json.JSONObject

data class RecordedNetworkRequest(
    val url: String,
    val method: String,
    val requestHeaders: Map<String, String>,
    val requestBody: String?,
    val status: Int,
    val statusText: String,
    val responseHeaders: Map<String, String>,
    val responseBody: String?,
    val duration: Int
) {
    companion object {
        fun fromJson(json: JSONObject): RecordedNetworkRequest =
            fromJson(Json.parseToJsonElement(json.toString()).jsonObject)

        /**
         * Reads the request the editor recorded. Fails with IllegalArgumentException
         * when a required field is missing or can't be read as its type.
         */
        internal fun fromJson(json: JsonObject): RecordedNetworkRequest {
            return RecordedNetworkRequest(
                url = json.requireString("url"),
                method = json.requireString("method"),
                requestHeaders = headers(json, "requestHeaders"),
                requestBody = json.optText("requestBody")?.takeIf { it.isNotEmpty() },
                status = json.requireLong("status").toInt(),
                statusText = json.optText("statusText") ?: "",
                responseHeaders = headers(json, "responseHeaders"),
                responseBody = json.optText("responseBody")?.takeIf { it.isNotEmpty() },
                duration = json.requireLong("duration").toInt()
            )
        }

        private fun headers(json: JsonObject, name: String): Map<String, String> {
            val headers = requireNotNull(json[name] as? JsonObject) { "The '$name' field isn't an object" }
            return headers.mapValues { (_, value) -> value.text() }
        }
    }
}
