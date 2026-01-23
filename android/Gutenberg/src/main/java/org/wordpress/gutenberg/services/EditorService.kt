package org.wordpress.gutenberg.services

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.wordpress.gutenberg.EditorHTTPClient
import org.wordpress.gutenberg.EditorHTTPClientProtocol
import org.wordpress.gutenberg.Paths
import org.wordpress.gutenberg.RESTAPIRepository
import org.wordpress.gutenberg.model.EditorAssetBundle
import org.wordpress.gutenberg.model.EditorCachePolicy
import org.wordpress.gutenberg.model.EditorConfiguration
import org.wordpress.gutenberg.model.EditorDependencies
import org.wordpress.gutenberg.model.EditorPreloadList
import org.wordpress.gutenberg.model.EditorProgress
import org.wordpress.gutenberg.model.EditorProgressCallback
import org.wordpress.gutenberg.model.EditorSettings
import org.wordpress.gutenberg.model.http.EditorURLResponse
import org.wordpress.gutenberg.stores.EditorAssetsLibrary
import org.wordpress.gutenberg.stores.EditorURLCache
import java.io.File

/**
 * Coordinates downloading and caching of editor dependencies from a WordPress site.
 *
 * `EditorService` handles fetching and caching all resources needed to display the
 * Gutenberg block editor, including editor settings, plugin assets, and REST API data.
 * It reports progress during the preparation phase and provides cleanup methods for
 * managing disk space.
 *
 * ## Usage
 *
 * ```kotlin
 * val service = EditorService(context, configuration)
 * val dependencies = service.prepare { progress ->
 *     println("Loading: ${progress.fractionCompleted * 100}%")
 * }
 * ```
 */
class EditorService(
    private val configuration: EditorConfiguration,
    private val restRepository: RESTAPIRepository,
    private val assetLibrary: EditorAssetsLibrary,
    private val sharedPreferences: SharedPreferences? = null
) {
    private val mutex = Mutex()
    private var progress: EditorProgress? = null
    private var progressCallback: EditorProgressCallback? = null

    /**
     * Weight values for different dependency types used for progress calculation.
     */
    enum class DependencyWeights(val weight: Double) {
        EDITOR_SETTINGS(10.0),
        ASSET_BUNDLE(50.0),
        POST(10.0),
        POST_TYPE(10.0),
        ACTIVE_THEME(10.0),
        SETTINGS_OPTIONS(10.0),
        POST_TYPES(10.0);

        companion object {
            val total: Double = entries.sumOf { it.weight }
        }
    }

    companion object {
        private const val ONCE_EVERY_PREFIX = "once-every-"
        private const val CLEANUP_INTERVAL_SECONDS = 86_400L // 1 day

        /**
         * Creates an EditorService with the standard dependencies.
         *
         * @param context The Android context.
         * @param configuration The editor configuration specifying site credentials and settings.
         * @param httpClient An optional HTTP client for making API requests. If null, a default
         *                   client is created using the configuration's auth header.
         * @param cachePolicy The cache policy to use for caching responses.
         * @param storageRoot The directory for storing downloaded asset bundles. If null, uses
         *                    a default location based on the site ID.
         * @param cacheRoot The directory for caching API responses. If null, uses a default
         *                  location based on the site ID.
         */
        fun create(
            context: Context,
            configuration: EditorConfiguration,
            httpClient: EditorHTTPClientProtocol? = null,
            cachePolicy: EditorCachePolicy = EditorCachePolicy.Always,
            coroutineScope: CoroutineScope,
            storageRoot: File? = null,
            tempStorageRoot: File? = null,
            cacheRoot: File? = null
        ): EditorService {
            val client = httpClient ?: EditorHTTPClient(authHeader = configuration.authHeader)

            val restRepository = RESTAPIRepository(
                configuration = configuration,
                httpClient = client,
                cache = EditorURLCache(
                    cacheRoot = cacheRoot ?: Paths.cacheRoot(context, configuration),
                    cachePolicy = cachePolicy
                )
            )

            val assetLibrary = EditorAssetsLibrary(
                configuration = configuration,
                httpClient = client,
                cachePolicy = cachePolicy,
                storageRoot = storageRoot ?: Paths.storageRoot(context, configuration),
                tempStorageRoot = tempStorageRoot ?: Paths.defaultTempStorageRoot(context)
            )

            val sharedPrefs = context.getSharedPreferences("EditorService", Context.MODE_PRIVATE)

            return EditorService(
                configuration = configuration,
                restRepository = restRepository,
                assetLibrary = assetLibrary,
                sharedPreferences = sharedPrefs
            )
        }

        /**
         * Creates an EditorService for testing without requiring a Context.
         *
         * @param configuration The editor configuration specifying site credentials and settings.
         * @param httpClient The HTTP client for making API requests.
         * @param cachePolicy The cache policy to use for caching responses.
         * @param storageRoot The directory for storing downloaded asset bundles.
         * @param cacheRoot The directory for caching API responses.
         */
        fun createForTesting(
            configuration: EditorConfiguration,
            httpClient: EditorHTTPClientProtocol,
            cachePolicy: EditorCachePolicy = EditorCachePolicy.Always,
            coroutineScope: CoroutineScope,
            storageRoot: File,
            tempStorageRoot: File,
            cacheRoot: File
        ): EditorService {
            val restRepository = RESTAPIRepository(
                configuration = configuration,
                httpClient = httpClient,
                cache = EditorURLCache(
                    cacheRoot = cacheRoot,
                    cachePolicy = cachePolicy
                )
            )

            val assetLibrary = EditorAssetsLibrary(
                configuration = configuration,
                httpClient = httpClient,
                cachePolicy = cachePolicy,
                storageRoot = storageRoot,
                tempStorageRoot = tempStorageRoot
            )

            return EditorService(
                configuration = configuration,
                restRepository = restRepository,
                assetLibrary = assetLibrary,
                sharedPreferences = null
            )
        }
    }

    /**
     * Returns the number of asset bundles currently stored on disk.
     */
    fun fetchAssetBundleCount(): Int {
        return assetLibrary.readAssetBundles().size
    }

    /**
     * Downloads any missing editor dependencies, reporting progress along the way.
     *
     * This method fetches editor settings, plugin assets, and preload data concurrently,
     * caching results for future use. If offline mode is enabled, returns empty dependencies.
     *
     * @param progress A callback invoked with progress updates during loading.
     * @return The complete set of dependencies needed to initialize the editor.
     * @throws Exception if any required resource fails to download.
     */
    suspend fun prepare(progress: EditorProgressCallback? = null): EditorDependencies {
        if (configuration.enableOfflineMode) {
            return EditorDependencies(
                editorSettings = EditorSettings.undefined,
                assetBundle = EditorAssetBundle.empty,
                preloadList = null
            )
        }

        mutex.withLock {
            this.progress = EditorProgress(completed = 1, total = 100)
            this.progressCallback = progress
        }

        return coroutineScope {
            val settingsDeferred = async { prepareEditorSettings() }
            val assetBundleDeferred = async { prepareAssetBundleIfEnabled() }
            val preloadListDeferred = async { preparePreloadList() }

            // Automatically clean up old asset bundles
            onceEvery(CLEANUP_INTERVAL_SECONDS, "cleanup") {
                cleanup()
            }

            EditorDependencies(
                editorSettings = settingsDeferred.await(),
                assetBundle = assetBundleDeferred.await(),
                preloadList = preloadListDeferred.await()
            )
        }
    }

    /**
     * Clear unused on-disk resources associated with this service's configuration.
     *
     * Calling this method will preserve the most recent cache entries, ensuring that
     * the editor still loads quickly without continuing to use unnecessary disk space.
     * Use this method to regularly clean up unused editor assets.
     */
    fun cleanup() {
        assetLibrary.cleanup()
        restRepository.cleanup()
    }

    /**
     * Clear all on-disk resources associated with this service's configuration, even ones
     * that may be in-use.
     *
     * Use this method rarely, as it will require re-downloading assets before the editor
     * is usable again.
     */
    fun purge() {
        assetLibrary.purge()
        restRepository.purge()
    }

    private suspend fun incrementProgress(weight: DependencyWeights, fraction: Double = 1.0) {
        mutex.withLock {
            val currentProgress = progress
            requireNotNull(currentProgress) {
                "Progress has not been initialized. This is a bug in the EditorService."
            }

            val newProgress = EditorProgress(
                completed = currentProgress.completed + (weight.weight * fraction).toInt(),
                total = currentProgress.total
            )
            progress = newProgress
            progressCallback?.invoke(newProgress)
        }
    }

    private suspend fun prepareEditorSettings(): EditorSettings {
        val cachedSettings = restRepository.readEditorSettings()
        if (cachedSettings != null) {
            incrementProgress(DependencyWeights.EDITOR_SETTINGS)
            return cachedSettings
        }

        val settings = restRepository.fetchEditorSettings()
        incrementProgress(DependencyWeights.EDITOR_SETTINGS)
        return settings
    }

    private suspend fun prepareAssetBundleIfEnabled(): EditorAssetBundle {
        if (!configuration.plugins) {
            incrementProgress(DependencyWeights.ASSET_BUNDLE)
            return EditorAssetBundle.empty
        }

        return prepareAssetBundle()
    }

    private suspend fun prepareAssetBundle(): EditorAssetBundle {
        val latestAssetBundle = assetLibrary.readAssetBundles().firstOrNull()
        if (latestAssetBundle != null) {
            incrementProgress(DependencyWeights.ASSET_BUNDLE)
            return latestAssetBundle
        }

        return assetLibrary.downloadAssetBundle { bundleProgress ->
            incrementProgress(DependencyWeights.ASSET_BUNDLE, bundleProgress.fractionCompleted)
        }
    }

    private suspend fun preparePreloadList(): EditorPreloadList {
        return coroutineScope {
            val activeThemeDeferred = async { prepareActiveTheme() }
            val settingsOptionsDeferred = async { prepareSettingsOptions() }
            val postTypeDataDeferred = async { preparePostType(configuration.postType) }
            val postTypesDataDeferred = async { preparePostTypes() }

            val postId = configuration.postId
            if (postId != null) {
                val postDataDeferred = async { preparePost(postId) }

                EditorPreloadList(
                    postID = postId,
                    postData = postDataDeferred.await(),
                    postType = configuration.postType,
                    postTypeData = postTypeDataDeferred.await(),
                    postTypesData = postTypesDataDeferred.await(),
                    activeThemeData = activeThemeDeferred.await(),
                    settingsOptionsData = settingsOptionsDeferred.await()
                )
            } else {
                EditorPreloadList(
                    postType = configuration.postType,
                    postTypeData = postTypeDataDeferred.await(),
                    postTypesData = postTypesDataDeferred.await(),
                    activeThemeData = activeThemeDeferred.await(),
                    settingsOptionsData = settingsOptionsDeferred.await()
                )
            }
        }
    }

    private suspend fun preparePost(id: Int): EditorURLResponse {
        val cachedPost = restRepository.readPost(id)
        if (cachedPost != null) {
            incrementProgress(DependencyWeights.POST)
            return cachedPost
        }

        val postData = restRepository.fetchPost(id)
        incrementProgress(DependencyWeights.POST)
        return postData
    }

    private suspend fun preparePostType(type: String): EditorURLResponse {
        val cachedPostType = restRepository.readPostType(type)
        if (cachedPostType != null) {
            incrementProgress(DependencyWeights.POST_TYPE)
            return cachedPostType
        }

        val response = restRepository.fetchPostType(type)
        incrementProgress(DependencyWeights.POST_TYPE)
        return response
    }

    private suspend fun prepareActiveTheme(): EditorURLResponse {
        val cachedActiveTheme = restRepository.readActiveTheme()
        if (cachedActiveTheme != null) {
            incrementProgress(DependencyWeights.ACTIVE_THEME)
            return cachedActiveTheme
        }

        val response = restRepository.fetchActiveTheme()
        incrementProgress(DependencyWeights.ACTIVE_THEME)
        return response
    }

    private suspend fun prepareSettingsOptions(): EditorURLResponse {
        val cachedSettingsOptions = restRepository.readSettingsOptions()
        if (cachedSettingsOptions != null) {
            incrementProgress(DependencyWeights.SETTINGS_OPTIONS)
            return cachedSettingsOptions
        }

        val response = restRepository.fetchSettingsOptions()
        incrementProgress(DependencyWeights.SETTINGS_OPTIONS)
        return response
    }

    private suspend fun preparePostTypes(): EditorURLResponse {
        val cachedPostTypes = restRepository.readPostTypes()
        if (cachedPostTypes != null) {
            incrementProgress(DependencyWeights.POST_TYPES)
            return cachedPostTypes
        }

        val response = restRepository.fetchPostTypes()
        incrementProgress(DependencyWeights.POST_TYPES)
        return response
    }

    /**
     * Executes the given work only if the specified duration has passed since the last execution.
     *
     * @param intervalSeconds The minimum interval in seconds between executions.
     * @param handle A unique identifier for this operation.
     * @param work The work to execute.
     */
    private fun onceEvery(intervalSeconds: Long, handle: String, work: () -> Unit) {
        val prefs = sharedPreferences ?: return

        val key = ONCE_EVERY_PREFIX + handle
        val lastRunTimestamp = prefs.getLong(key, 0L)
        val currentTime = System.currentTimeMillis() / 1000

        if (lastRunTimestamp + intervalSeconds <= currentTime) {
            work()
            prefs.edit().putLong(key, currentTime).apply()
        }
    }
}
