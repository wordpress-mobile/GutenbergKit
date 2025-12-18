package org.wordpress.gutenberg.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.security.MessageDigest

/**
 * A raw manifest response from the WordPress editor-assets API endpoint.
 *
 * This class represents the unprocessed server response containing HTML script and style
 * tags as raw strings. It computes a checksum of the original data to detect changes.
 *
 * Use `LocalEditorAssetManifest` for a processed version with parsed URLs.
 */
data class RemoteEditorAssetManifest(
    /** The raw HTML containing `<script>` tags from the server. */
    val scripts: String,
    /** The raw HTML containing `<link>` stylesheet tags from the server. */
    val styles: String,
    /** The list of block type identifiers allowed by the site (e.g., "core/paragraph"). */
    val allowedBlockTypes: List<String>,
    /**
     * A SHA-256 checksum of the original JSON data.
     *
     * Used to detect when the manifest has changed and assets need to be re-downloaded.
     */
    val checksum: String
) {
    /**
     * The JSON structure returned by the server.
     */
    @Serializable
    data class RawManifest(
        val scripts: String,
        val styles: String,
        @SerialName("allowed_block_types")
        val allowedBlockTypes: List<String>
    ) {
        companion object {
            val empty = RawManifest(scripts = "", styles = "", allowedBlockTypes = emptyList())
        }
    }

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        /**
         * Creates a remote manifest from raw JSON data.
         *
         * @param data The JSON response from the editor-assets endpoint.
         * @throws Exception A decoding error if the JSON is malformed.
         */
        fun fromData(data: String): RemoteEditorAssetManifest {
            val checksum = data.sha256()
            val rawManifest = json.decodeFromString<RawManifest>(data)
            return RemoteEditorAssetManifest(
                scripts = rawManifest.scripts,
                styles = rawManifest.styles,
                allowedBlockTypes = rawManifest.allowedBlockTypes,
                checksum = checksum
            )
        }
    }
}

private fun String.sha256(): String {
    val bytes = this.toByteArray()
    val md = MessageDigest.getInstance("SHA-256")
    val digest = md.digest(bytes)
    return digest.joinToString("") { "%02x".format(it) }
}
