package org.wordpress.gutenberg

import com.google.gson.Gson
import com.google.gson.JsonObject

data class JsExceptionStackTraceElement (
    val fileName: String?,
    val lineNumber: Int?,
    val colNumber: Int?,
    val function: String,
)
class GutenbergJsException (
    val type: String,
    val message: String,
    var stackTrace: List<JsExceptionStackTraceElement>,
    val context: Map<String, Any> = emptyMap(),
    val tags: Map<String,String> = emptyMap(),
    val isHandled: Boolean,
    val handledBy: String
) {

    companion object {
        @JvmStatic
        fun fromString(exceptionString: String): GutenbergJsException {
            val gson = Gson()
            val rawException = gson.fromJson(exceptionString, JsonObject::class.java)

            val type = rawException.get("type")?.asString ?: ""
            val message = rawException.get("message")?.asString ?: ""

            val stackTrace = rawException.getAsJsonArray("stacktrace")?.map { element ->
                val stackTraceElement = element.asJsonObject
                val stackTraceFunction = stackTraceElement.get("function")?.asString
                stackTraceFunction?.let {
                    JsExceptionStackTraceElement(
                        stackTraceElement.get("filename")?.asString,
                        stackTraceElement.get("lineno")?.asInt,
                        stackTraceElement.get("colno")?.asInt,
                        stackTraceFunction
                    )
                }
            }?.filterNotNull() ?: emptyList()

            val context = rawException.getAsJsonObject("context")?.entrySet()?.associate {
                it.key to it.value.asString
            } ?: emptyMap()

            val tags = rawException.getAsJsonObject("tags")?.entrySet()?.associate {
                it.key to it.value.asString
            } ?: emptyMap()

            val isHandled = rawException.get("isHandled")?.asBoolean ?: false
            val handledBy = rawException.get("handledBy")?.asString ?: ""

            return GutenbergJsException(
                type,
                message,
                stackTrace,
                context,
                tags,
                isHandled,
                handledBy
            )
        }
    }
}
