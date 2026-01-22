package org.wordpress.gutenberg.model

import android.annotation.SuppressLint
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement

/**
 * Editor configuration and styling data fetched from the WordPress REST API.
 *
 * This class wraps the raw JSON response from the block editor settings endpoint,
 * which contains theme colors, typography, spacing, and other customization options.
 * The raw JSON is injected directly into the editor's JavaScript.
 *
 * Theme styles are extracted separately for use in styling the editor UI.
 */
@SuppressLint("UnsafeOptInUsageError")
@Serializable
data class EditorSettings(
    val jsonValue: JsonElement? = null,
    /**
     * CSS styles extracted from the theme's global styles.
     *
     * Contains the concatenated CSS from all theme style entries.
     * Used to apply theme styling to the editor interface.
     */
    val themeStyles: String = "",
    val stringValue: String = ""
) {
    companion object {
        @Transient
        private val json = Json { ignoreUnknownKeys = true }

        /**
         * Creates editor settings from raw API response data.
         *
         * Parses the JSON to extract theme styles while preserving the raw string
         * for JavaScript injection. This operation involves JSON parsing and should
         * be cached.
         *
         * @param data The raw JSON string from the block editor settings endpoint.
         *             Must be valid JSON (empty or blank strings will throw).
         * @throws kotlinx.serialization.SerializationException if [data] is not valid JSON,
         *         including empty or blank strings.
         */
        fun fromData(data: String): EditorSettings {
            val jsonValue = json.parseToJsonElement(data)
            val stringValue = jsonValue.toString().orEmpty()

            val themeStyles = runCatching {
                json.decodeFromString<InternalEditorSettings>(data)
                    .styles
                    .mapNotNull { it.css }
                    .joinToString("\n")
            }.getOrDefault("")

            return EditorSettings(
                jsonValue = jsonValue,
                themeStyles = themeStyles,
                stringValue = stringValue
            )
        }

        /** A placeholder value for when editor settings are not available. */
        val undefined = EditorSettings(
            jsonValue = null,
            themeStyles = "undefined",
            stringValue = ""
        )
    }
}

/**
 * Internal structure for decoding the editor settings response.
 *
 * Only decodes the fields needed to extract theme styles.
 */
@Serializable
internal data class InternalEditorSettings(
    val styles: List<CSSStyle> = emptyList()
)

/**
 * A CSS style entry from the theme.
 */
@Serializable
internal data class CSSStyle(
    /** The CSS content, if present. */
    val css: String? = null,
    /** Whether this style is from the global styles system. */
    @SerialName("isGlobalStyles")
    val isGlobalStyles: Boolean = false
)
