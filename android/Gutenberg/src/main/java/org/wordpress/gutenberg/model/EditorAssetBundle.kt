package org.wordpress.gutenberg.model

import android.util.Log
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.util.Date

private const val TAG = "EditorAssetBundle"

/**
 * A collection of editor assets downloaded from a WordPress site.
 *
 * The asset bundle contains both the manifest (describing what assets are needed)
 * and serves as the root directory for cached asset files. Assets are stored
 * in a directory structure mirroring their original URL paths.
 *
 * ## Lifecycle
 *
 * 1. A bundle is created with a manifest from the server
 * 2. Assets are downloaded and stored within the bundle's root directory
 * 3. The bundle is persisted to disk with its metadata
 * 4. On subsequent launches, the bundle can be loaded from disk and validated
 *
 * ## Identification
 *
 * Each bundle has an `id` derived from its manifest's checksum. This ensures that
 * when a site's assets change, a new bundle will be created with a different ID,
 * allowing old bundles to be cleaned up.
 */
data class EditorAssetBundle(
    /** The parsed manifest describing the assets in this bundle. */
    val manifest: LocalEditorAssetManifest,
    /** When this bundle was downloaded from the server. */
    val downloadDate: Date,
    /** The root directory where this bundle's assets are stored. */
    val bundleRoot: File
) {
    /**
     * A unique identifier for this bundle based on its manifest content.
     *
     * Returns "empty" for bundles with empty manifests, otherwise returns
     * the manifest's SHA-256 checksum.
     */
    val id: String
        get() = manifest.checksum

    /**
     * The total number of assets (scripts + styles) that need to be cached.
     */
    val assetCount: Int
        get() = manifest.assetUrls.size

    /**
     * A raw bundle structure for JSON serialization.
     */
    @Serializable
    data class RawAssetBundle(
        val manifest: LocalEditorAssetManifest,
        val downloadDate: Long // Unix timestamp in milliseconds
    ) {
        constructor(manifest: LocalEditorAssetManifest, downloadDate: Date) : this(
            manifest = manifest,
            downloadDate = downloadDate.time
        )

        fun toEditorAssetBundle(bundleRoot: File): EditorAssetBundle {
            return EditorAssetBundle(
                manifest = manifest,
                downloadDate = Date(downloadDate),
                bundleRoot = bundleRoot
            )
        }
    }

    companion object {
        private val json = Json { ignoreUnknownKeys = true }
        private const val MANIFEST_FILENAME = "manifest.json"
        private const val EDITOR_REPRESENTATION_FILENAME = "editor-representation.json"

        /**
         * An empty bundle for sites that don't support the editor-assets endpoint.
         */
        val empty = EditorAssetBundle(
            manifest = LocalEditorAssetManifest.empty,
            downloadDate = Date(),
            bundleRoot = File("/tmp/empty-bundle")
        )

        /**
         * Loads a bundle from a manifest file URL.
         *
         * @param file The file containing the serialized bundle manifest.
         * @throws Exception if the file cannot be read or parsed.
         */
        fun fromFile(file: File): EditorAssetBundle {
            val data = file.readText()
            val rawBundle = json.decodeFromString<RawAssetBundle>(data)
            return rawBundle.toEditorAssetBundle(file.parentFile ?: file)
        }
    }

    /**
     * Creates a bundle with the current time as the download date.
     */
    constructor(manifest: LocalEditorAssetManifest, bundleRoot: File) : this(
        manifest = manifest,
        downloadDate = Date(),
        bundleRoot = bundleRoot
    )

    /**
     * Checks if the asset data exists for a given URL.
     *
     * @param url The original asset URL.
     * @return `true` if the asset has been cached locally.
     */
    fun hasAssetData(url: String): Boolean {
        if(this == empty) {
            return false
        }

        return assetDataPath(url).exists()
    }

    /**
     * Returns the local file path where an asset should be stored.
     *
     * The path is constructed by appending the URL's path component to
     * the bundle's root directory.
     *
     * Note: This method must not be called on [EditorAssetBundle.empty].
     * In debug builds, an assertion will catch this misuse.
     *
     * @param url The original asset URL.
     * @return The file where the asset is (or should be) stored.
     * @throws IllegalArgumentException if the URL path would escape the bundle root.
     */
    fun assetDataPath(url: String): File {
        assert(this != empty) { "Cannot get asset path from empty bundle" }

        val urlPath = java.net.URL(url).path
        val resolvedFile = File(bundleRoot, urlPath).canonicalFile
        val bundleRootCanonical = bundleRoot.canonicalFile

        require(
            resolvedFile.path.startsWith(bundleRootCanonical.path + File.separator) ||
                resolvedFile.path == bundleRootCanonical.path
        ) {
            "Asset path escapes bundle root: $urlPath"
        }

        return resolvedFile
    }

    /**
     * Reads the cached asset data for a given URL.
     *
     * @param url The original asset URL.
     * @return The asset's binary data.
     * @throws Exception if the asset has not been cached.
     */
    fun assetData(url: String): ByteArray {
        return assetDataPath(url).readBytes()
    }

    /**
     * Stores the editor representation for later retrieval.
     *
     * The editor representation is the processed manifest with rewritten URLs
     * ready for injection into the WebView.
     *
     * @param representation The processed manifest to store.
     */
    fun setEditorRepresentation(representation: RemoteEditorAssetManifest.RawManifest) {
        val file = File(bundleRoot, EDITOR_REPRESENTATION_FILENAME)
        val data = json.encodeToString(representation)
        file.writeText(data)
        Log.d(TAG, "Wrote editor representation: file=${file.absolutePath}, size=${data.length} bytes")
    }

    /**
     * Retrieves the stored editor representation.
     *
     * @return The stored representation.
     * @throws Exception if no representation has been stored.
     */
    fun getEditorRepresentation(): RemoteEditorAssetManifest.RawManifest {
        val file = File(bundleRoot, EDITOR_REPRESENTATION_FILENAME)
        val data = file.readText()
        return json.decodeFromString<RemoteEditorAssetManifest.RawManifest>(data)
    }

    /**
     * Retrieves the stored editor representation as a map for JSON serialization.
     *
     * @return A map representation suitable for JSON injection.
     * @throws Exception if no representation has been stored.
     */
    fun getEditorRepresentationAsMap(): Map<String, Any> {
        val rep = getEditorRepresentation()
        return mapOf(
            "scripts" to rep.scripts,
            "styles" to rep.styles,
            "allowed_block_types" to rep.allowedBlockTypes
        )
    }

    /**
     * Saves the bundle's metadata to disk.
     *
     * Call this after downloading all assets to persist the bundle for future sessions.
     */
    fun save() {
        val rawBundle = RawAssetBundle(manifest = manifest, downloadDate = downloadDate)
        val file = File(bundleRoot, MANIFEST_FILENAME)
        val data = json.encodeToString(rawBundle)
        file.writeText(data)
        Log.d(TAG, "Wrote asset bundle manifest: file=${file.absolutePath}, size=${data.length} bytes")
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is EditorAssetBundle) return false
        return manifest == other.manifest && downloadDate == other.downloadDate
    }

    override fun hashCode(): Int {
        var result = manifest.hashCode()
        result = 31 * result + downloadDate.hashCode()
        return result
    }
}
