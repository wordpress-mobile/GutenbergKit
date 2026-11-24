package org.wordpress.gutenberg

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull

/**
 * A message the editor page posts to the native bridge, as
 * `{ "message": name, "body": { ... } }`: the same shape iOS receives.
 *
 * The body stays a parsed tree, so a large payload such as the inserter's is
 * read once and decoded from the tree rather than written out and read again.
 */
internal data class EditorBridgeMessage(val name: String, val body: JsonObject) {
    companion object {
        /**
         * Parses [json], or returns null when it isn't an object with a string
         * `message` and, if present, an object `body`. A missing body is empty.
         */
        fun parse(json: String): EditorBridgeMessage? {
            val message = runCatching { Json.parseToJsonElement(json) }.getOrNull() as? JsonObject ?: return null
            val name = (message["message"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
            val body = when (val rawBody = message["body"]) {
                null -> JsonObject(emptyMap())
                is JsonObject -> rawBody
                else -> return null
            }
            return EditorBridgeMessage(name, body)
        }
    }
}

// The readers below match org.json's getters, which read these bodies before:
// they accept a value written as a string, and fail with IllegalArgumentException
// when the field is missing or can't be read as the type.

/** Reads the boolean field [name]. */
internal fun JsonObject.requireBoolean(name: String): Boolean =
    requireNotNull(primitive(name)?.booleanOrNull) { "The '$name' field isn't a boolean" }

/** Reads the whole-number field [name], dropping any fraction. */
internal fun JsonObject.requireLong(name: String): Long =
    requireNotNull(get(name)?.asLongOrNull()) { "The '$name' field isn't a number" }

/** This value as a whole number, dropping any fraction, or null when it isn't a number. */
internal fun JsonElement.asLongOrNull(): Long? =
    (this as? JsonPrimitive)?.let { it.longOrNull ?: it.doubleOrNull?.toLong() }

/** Reads the string field [name]. */
internal fun JsonObject.requireString(name: String): String =
    requireNotNull(primitive(name)?.takeUnless { it is JsonNull }?.content) { "The '$name' field isn't a string" }

/** Reads the field [name] as text, as org.json's `optString` does: `"null"` for null, and null when missing. */
internal fun JsonObject.optText(name: String): String? = get(name)?.text()

/** This value as org.json writes it with `getString`: a primitive's content, or a structure's JSON. */
internal fun JsonElement.text(): String = (this as? JsonPrimitive)?.content ?: toString()

private fun JsonObject.primitive(name: String): JsonPrimitive? = get(name) as? JsonPrimitive
