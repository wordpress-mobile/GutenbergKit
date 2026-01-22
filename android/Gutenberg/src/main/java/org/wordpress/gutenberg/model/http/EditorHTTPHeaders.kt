package org.wordpress.gutenberg.model.http

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * A case-insensitive collection of HTTP headers.
 *
 * This class provides a type-safe way to work with HTTP headers, with case-insensitive
 * key lookups as required by the HTTP specification. Headers are `Serializable` for JSON encoding.
 *
 * Example usage:
 * ```kotlin
 * val headers = EditorHTTPHeaders(mapOf("Content-Type" to "application/json"))
 * headers["accept"] = "text/html"  // Case-insensitive
 * println(headers["CONTENT-TYPE"])   // "application/json"
 * ```
 */
@Serializable(with = EditorHTTPHeadersSerializer::class)
class EditorHTTPHeaders(
    elements: Map<String, String> = emptyMap()
) {
    private val elements: MutableMap<String, String> = elements.toMutableMap()

    /**
     * Accesses the header value for the given key using case-insensitive matching.
     *
     * When getting a value, the key is matched case-insensitively against stored headers.
     * When setting a value, the new key will replace the old key case-insensitively.
     *
     * @param key The header name to look up or set.
     * @return The header value, or `null` if no matching header exists.
     */
    operator fun get(key: String): String? {
        val lowercasedKey = key.lowercase()
        return elements.entries.firstOrNull { it.key.lowercase() == lowercasedKey }?.value
    }

    operator fun set(key: String, value: String?) {
        val lowercasedKey = key.lowercase()
        // Remove any existing key with same case-insensitive match
        val existingKey = elements.keys.firstOrNull { it.lowercase() == lowercasedKey }
        if (existingKey != null) {
            elements.remove(existingKey)
        }
        if (value != null) {
            elements[key] = value
        }
    }

    /**
     * Returns the headers as a standard string map.
     *
     * Useful for passing headers to HTTP request APIs.
     */
    val dictionaryValue: Map<String, String>
        get() = elements.toMap()

    fun toJsonElement(): JsonElement {
        return JsonObject(elements.mapValues { JsonPrimitive(it.value) })
    }

    /**
     * Returns a new headers collection containing only the specified keys.
     *
     * Key matching is case-insensitive for filtering.
     *
     * @param keys The header names to include.
     * @return A new `EditorHTTPHeaders` containing only the matching headers.
     */
    fun filtering(vararg keys: String): EditorHTTPHeaders {
        val lowercasedKeys = keys.map { it.lowercase() }
        val filtered = elements.filter { lowercasedKeys.contains(it.key.lowercase()) }
        return EditorHTTPHeaders(filtered)
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is EditorHTTPHeaders) return false
        if (elements.size != other.elements.size) return false
        for ((key, value) in elements) {
            if (other[key] != value) return false
        }
        return true
    }

    override fun hashCode(): Int {
        // Use lowercase keys for consistent hashing
        return elements.entries.sumOf {
            it.key.lowercase().hashCode() + it.value.hashCode()
        }
    }

    companion object {
        val empty = EditorHTTPHeaders()
    }
}

object EditorHTTPHeadersSerializer : KSerializer<EditorHTTPHeaders> {
    private val delegateSerializer = MapSerializer(String.serializer(), String.serializer())

    override val descriptor: SerialDescriptor = delegateSerializer.descriptor

    override fun serialize(encoder: Encoder, value: EditorHTTPHeaders) {
        encoder.encodeSerializableValue(delegateSerializer, value.dictionaryValue)
    }

    override fun deserialize(decoder: Decoder): EditorHTTPHeaders {
        val map = decoder.decodeSerializableValue(delegateSerializer)
        return EditorHTTPHeaders(map)
    }
}
