package org.wordpress.gutenberg

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
        fun fromJson(json: JSONObject): RecordedNetworkRequest {
            return RecordedNetworkRequest(
                url = json.getString("url"),
                method = json.getString("method"),
                requestHeaders = jsonObjectToMap(json.getJSONObject("requestHeaders")),
                requestBody = json.optString("requestBody").takeIf { it.isNotEmpty() },
                status = json.getInt("status"),
                statusText = json.optString("statusText", ""),
                responseHeaders = jsonObjectToMap(json.getJSONObject("responseHeaders")),
                responseBody = json.optString("responseBody").takeIf { it.isNotEmpty() },
                duration = json.getInt("duration")
            )
        }

        private fun jsonObjectToMap(jsonObject: JSONObject): Map<String, String> {
            val map = mutableMapOf<String, String>()
            val keys = jsonObject.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                map[key] = jsonObject.getString(key)
            }
            return map
        }
    }
}
