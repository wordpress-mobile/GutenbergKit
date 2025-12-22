package org.wordpress.gutenberg.stores

import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.wordpress.gutenberg.EditorHTTPClientProtocol
import org.wordpress.gutenberg.model.EditorAssetBundle
import org.wordpress.gutenberg.model.EditorCachePolicy
import org.wordpress.gutenberg.model.EditorConfiguration
import org.wordpress.gutenberg.model.EditorProgress
import org.wordpress.gutenberg.model.EditorProgressCallback
import org.wordpress.gutenberg.model.LocalEditorAssetManifest
import org.wordpress.gutenberg.model.RemoteEditorAssetManifest
import java.io.File
import java.net.URL
import java.util.Date
import java.util.UUID

/**
 * The Editor Asset Library is a site-specific repository of remote assets that can be downloaded
 * to the local device to support plugins and theme styles.
 */
class EditorAssetsLibrary(
    private val configuration: EditorConfiguration,
    private val httpClient: EditorHTTPClientProtocol,
    private val cachePolicy: EditorCachePolicy = EditorCachePolicy.Always,
    private val coroutineScope: CoroutineScope,
    private val storageRoot: File
) {
    private val mutex = Mutex()

    companion object {
        private const val TAG = "EditorAssetsLibrary"
        private const val MANIFEST_FILENAME = "manifest.json"
        private val SUPPORTED_EXTENSIONS = listOf(".js", ".css", ".js.map")
    }

    init {
        if (!storageRoot.exists()) {
            storageRoot.mkdirs()
        }
    }

    // MARK: - Manifest Handling

    /**
     * Retrieve the manifest for a given site configuration.
     *
     * Applications should periodically check for a new editor manifest. This can be very expensive,
     * so this method defaults to returning an existing one on-disk based on the library's cache policy.
     */
    suspend fun fetchManifest(): LocalEditorAssetManifest =
        withContext(Dispatchers.IO) {
            if (!configuration.plugins) {
                return@withContext LocalEditorAssetManifest.empty
            }

            val url = editorAssetsUrl(configuration)
            val response = httpClient.perform("GET", url)
            val remoteManifest = RemoteEditorAssetManifest.fromData(response.stringData)

            val downloadDate = existingBundleDownloadDate(remoteManifest.checksum)

            if(downloadDate == null) {
                return@withContext LocalEditorAssetManifest.fromRemoteManifest(remoteManifest)
            }

            if (cachePolicy.allowsResponseWith(downloadDate)) {
                val existingBundle = existingBundle(remoteManifest.checksum)
                if (existingBundle != null) {
                    return@withContext existingBundle.manifest
                }
            }

            LocalEditorAssetManifest.fromRemoteManifest(remoteManifest)
        }

    /**
     * Returns the download date for an existing bundle with the given checksum, or null if not found.
     */
    private fun existingBundleDownloadDate(checksum: String): Date? {
        return existingBundle(checksum)?.downloadDate
    }

    // MARK: - Bundle Handling

    /**
     * The downloaded asset bundles for a given `EditorConfiguration`. Ordered newest to oldest.
     */
    fun readAssetBundles(): List<EditorAssetBundle> {
        if (!storageRoot.exists()) {
            storageRoot.mkdirs()
        }

        return storageRoot.listFiles()
            ?.filter { it.isDirectory }
            ?.filter { !it.name.endsWith(".download") } // Don't include bundles being downloaded
            ?.mapNotNull { dir ->
                val manifestFile = File(dir, MANIFEST_FILENAME)
                if (manifestFile.exists()) {
                    try {
                        EditorAssetBundle.fromFile(manifestFile)
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to load bundle from ${dir.name}", e)
                        null
                    }
                } else {
                    null
                }
            }
            ?.sortedByDescending { it.downloadDate }
            ?: emptyList()
    }

    /**
     * Fetches the latest manifest from the server and downloads all of its resources, caching them on-disk.
     *
     * @param progress An optional callback that receives progress updates as assets are downloaded.
     * @return The downloaded `EditorAssetBundle` containing all cached assets.
     * @throws Exception if the manifest cannot be fetched or assets fail to download.
     */
    suspend fun downloadAssetBundle(
        progress: EditorProgressCallback? = null
    ): EditorAssetBundle {
        val manifest = fetchManifest()
        return buildBundle(manifest, progress)
    }

    /**
     * Checks whether a bundle with the given manifest checksum exists on disk.
     */
    fun hasBundle(checksum: String): Boolean {
        return bundleRoot(checksum).isDirectory
    }

    /**
     * Retrieves an existing bundle from disk if one exists for the given manifest checksum.
     */
    fun existingBundle(checksum: String): EditorAssetBundle? {
        if (!hasBundle(checksum)) {
            return null
        }

        return try {
            EditorAssetBundle.fromFile(bundleManifestPath(checksum))
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load existing bundle for checksum: $checksum", e)
            null
        }
    }

    // MARK: - Individual Asset Handling

    /**
     * Downloads all of the assets for a given manifest and assembles them into a bundle.
     *
     * Assets are downloaded concurrently and stored in a temporary directory. Once all downloads
     * complete successfully, the bundle is atomically moved to its final location.
     */
    suspend fun buildBundle(
        manifest: LocalEditorAssetManifest,
        progress: EditorProgressCallback? = null
    ): EditorAssetBundle = withContext(Dispatchers.IO) {
        // Don't bother building a bundle from an empty manifest
        if (manifest == LocalEditorAssetManifest.empty) {
            progress?.invoke(EditorProgress(completed = 100, total = 100))
            return@withContext EditorAssetBundle.empty
        }

        val tempDirectory = File(System.getProperty("java.io.tmpdir"), UUID.randomUUID().toString())
        tempDirectory.mkdirs()

        val bundle = EditorAssetBundle(
            manifest = manifest,
            bundleRoot = tempDirectory
        )

        // Write the manifest
        bundle.save()

        // Build and store the editor representation
        val editorRepresentation = manifest.buildEditorRepresentation(
            urlScheme = "https",
            shouldUsePlugins = configuration.plugins,
            shouldUseThemeStyles = configuration.themeStyles
        )
        bundle.setEditorRepresentation(editorRepresentation)

        // Download all assets concurrently
        val assets = (manifest.scripts + manifest.styles).filter { isSupportedAsset(it) }
        var completed = 0

        coroutineScope {
            val downloads = assets.map { assetUrl ->
                async {
                    fetchAsset(assetUrl, bundle)
                    mutex.withLock {
                        completed++
                        progress?.invoke(EditorProgress(completed = completed, total = assets.size))
                    }
                }
            }
            downloads.awaitAll()
        }

        // Move bundle to final location
        copyBundle(bundle, bundleRoot(bundle))
    }

    /**
     * Downloads a single asset and copies it into the temporary bundle directory.
     */
    private suspend fun fetchAsset(url: String, bundle: EditorAssetBundle): File =
        withContext(Dispatchers.IO) {
            val destinationPath = bundle.assetDataPath(url)
            val destinationParent = destinationPath.parentFile

            // Ensure the destination directory exists
            destinationParent?.mkdirs()

            // Download to destination
            val response = httpClient.download(url, destinationPath)
            Log.d(TAG, "Downloaded asset: ${URL(url).path.substringAfterLast('/')}")

            response.file
        }

    /**
     * Checks if the given URL is eligible to be downloaded into the local bundle.
     *
     * Only HTTP/HTTPS URLs with `.js`, `.css`, or `.js.map` extensions are supported.
     */
    private fun isSupportedAsset(url: String): Boolean {
        val parsedUrl = try {
            URL(url)
        } catch (e: Exception) {
            Log.w(TAG, "Unexpected asset link: $url")
            return false
        }

        val scheme = parsedUrl.protocol
        if (scheme != "http" && scheme != "https") {
            Log.w(TAG, "Unexpected asset link: $url")
            return false
        }

        val filename = parsedUrl.path.substringAfterLast('/')
        if (!SUPPORTED_EXTENSIONS.any { filename.endsWith(it) }) {
            Log.w(TAG, "Unsupported asset URL: $url")
            return false
        }

        return true
    }

    // MARK: - Helpers

    private fun editorAssetsUrl(configuration: EditorConfiguration): String {
        val baseUrl = configuration.siteApiRoot.trimEnd('/')
        return "$baseUrl/wpcom/v2/editor-assets?exclude=core,gutenberg"
    }

    /**
     * Cleans up outdated library entries for this site.
     *
     * This method removes all asset bundles except the most recent one, freeing disk space
     * while ensuring the editor can still load quickly with cached assets.
     */
    fun cleanup() {
        val bundles = readAssetBundles().drop(1)

        for (bundle in bundles) {
            try {
                bundleRoot(bundle).deleteRecursively()
            } catch (e: Exception) {
                Log.w(TAG, "Failed to remove bundle: ${bundle.id}", e)
            }
        }
    }

    /**
     * Erases all library entries for this site.
     *
     * This method removes all asset bundles, requiring assets to be re-downloaded
     * before the editor can be used again. Use sparingly.
     */
    fun purge() {
        if (!storageRoot.exists()) {
            return
        }

        storageRoot.deleteRecursively()
        storageRoot.mkdirs()
    }

    // MARK: - File Path Helpers

    private fun bundleRoot(bundle: EditorAssetBundle): File {
        require(bundle.id.isNotEmpty()) { "Bundle must have a valid ID" }
        return bundleRoot(bundle.id)
    }

    private fun bundleRoot(checksum: String): File {
        return File(storageRoot, checksum)
    }

    private fun bundleManifestPath(checksum: String): File {
        return File(bundleRoot(checksum), MANIFEST_FILENAME)
    }

    /**
     * Copies a bundle from its temporary location to its final destination.
     */
    private fun copyBundle(bundle: EditorAssetBundle, destination: File): EditorAssetBundle {
        if (destination.exists()) {
            destination.deleteRecursively()
        }

        bundle.bundleRoot.copyRecursively(destination, overwrite = true)

        // Clean up temp directory
        bundle.bundleRoot.deleteRecursively()

        return EditorAssetBundle.fromFile(File(destination, MANIFEST_FILENAME))
    }

    // MARK: - WebView Asset Caching Support
    // These methods support on-demand asset caching from the CachedAssetRequestInterceptor

    /**
     * Gets cached asset data from any downloaded bundle if available.
     *
     * This checks all downloaded bundles for the requested asset and returns
     * the data if found.
     *
     * @param url The original asset URL.
     * @return The asset's binary data, or null if not cached.
     */
    fun getCachedAsset(url: String): ByteArray? {
        val bundles = readAssetBundles()
        for (bundle in bundles) {
            if (bundle.hasAssetData(url)) {
                return try {
                    bundle.assetData(url)
                } catch (e: Exception) {
                    Log.w(TAG, "Error reading cached asset: $url", e)
                    null
                }
            }
        }
        return null
    }

    /**
     * Caches an asset in the background without blocking.
     *
     * This is used by CachedAssetRequestInterceptor to opportunistically cache
     * assets as they're requested by the WebView.
     *
     * @param url The URL of the asset to cache.
     */
    fun cacheAssetInBackground(url: String) {
        if (!isSupportedAsset(url)) return

        coroutineScope.launch {
            try {
                // Find the most recent bundle and add the asset to it
                val bundles = readAssetBundles()
                val bundle = bundles.firstOrNull()
                if (bundle != null && bundle != EditorAssetBundle.empty) {
                    val destinationPath = bundle.assetDataPath(url)
                    if (!destinationPath.exists()) {
                        destinationPath.parentFile?.mkdirs()
                        httpClient.download(url, destinationPath)
                        Log.d(TAG, "Background cached: $url")
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to background cache: $url", e)
            }
        }
    }
}
