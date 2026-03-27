package com.example.gutenbergkit

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import org.wordpress.gutenberg.model.EditorCachePolicy
import org.wordpress.gutenberg.model.EditorConfiguration
import org.wordpress.gutenberg.model.EditorDependencies
import org.wordpress.gutenberg.model.PostTypeDetails
import org.wordpress.gutenberg.services.EditorService
import rs.wordpress.api.kotlin.WpRequestResult
import uniffi.wp_api.PostType as WpPostType

data class SitePreparationUiState(
    val enableNativeInserter: Boolean = false,
    val enableInserterMediaStrip: Boolean = false,
    val enableNativeMediaUpload: Boolean = true,
    val enableNetworkLogging: Boolean = false,
    /** All viewable post types fetched from the site, or empty while loading. */
    val postTypes: List<PostTypeDetails> = emptyList(),
    /** The post type currently selected in the picker. Null until [postTypes] loads. */
    val selectedPostType: PostTypeDetails? = null,
    val cacheBundleCount: Int? = null,
    val isLoading: Boolean = false,
    val error: String? = null,
    val editorConfiguration: EditorConfiguration? = null,
    val editorDependencies: EditorDependencies? = null,
    val loadingProgress: Float? = null
)

class SitePreparationViewModel(
    application: Application,
    private val configurationItem: ConfigurationItem
) : AndroidViewModel(application) {

    private val _uiState = MutableStateFlow(SitePreparationUiState())
    val uiState: StateFlow<SitePreparationUiState> = _uiState.asStateFlow()

    private val siteCapabilitiesDiscovery = SiteCapabilitiesDiscovery()
    private val networkAvailabilityProvider =
        (application as GutenbergKitApplication).networkAvailabilityProvider

    fun startLoading() {
        viewModelScope.launch {
            try {
                val configuration = when (configurationItem) {
                    is ConfigurationItem.BundledEditor -> createBundledConfiguration()
                    is ConfigurationItem.LocalWordPress -> {
                        val credentials = LocalWordPressCredentials.load()
                            ?: throw IllegalStateException(
                                "Local WordPress not configured.\n\nRun 'make wp-env-start' from the project root, then rebuild the app."
                            )
                        try {
                            loadConfiguration(
                                ConfigurationItem.ConfiguredEditor(
                                    accountId = 0u,
                                    name = "Local WordPress",
                                    siteUrl = credentials.siteUrl,
                                    siteApiRoot = credentials.siteApiRoot,
                                    authHeader = credentials.authHeader
                                )
                            )
                        } catch (e: java.net.ConnectException) {
                            throw IllegalStateException(
                                "Could not connect to Local WordPress at ${credentials.siteUrl}.\n\nThe wp-env server may not be running. Start it with 'make wp-env-start'."
                            )
                        }
                    }
                    is ConfigurationItem.ConfiguredEditor -> loadConfiguration(configurationItem)
                }
                _uiState.update { it.copy(editorConfiguration = configuration) }
                countAssetBundles()
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message ?: "Unknown error") }
            }
        }
    }

    fun setEnableNativeInserter(enabled: Boolean) {
        _uiState.update { it.copy(enableNativeInserter = enabled) }
    }

    fun setEnableInserterMediaStrip(enabled: Boolean) {
        _uiState.update { it.copy(enableInserterMediaStrip = enabled) }
    }

    fun setEnableNativeMediaUpload(enabled: Boolean) {
        _uiState.update { it.copy(enableNativeMediaUpload = enabled) }
    }

    fun setEnableNetworkLogging(enabled: Boolean) {
        _uiState.update { it.copy(enableNetworkLogging = enabled) }
    }

    fun setPostType(postType: PostTypeDetails) {
        _uiState.update { it.copy(selectedPostType = postType) }
    }

    fun prepareEditor() {
        val configuration = _uiState.value.editorConfiguration ?: return

        val cacheIntervalSeconds = 86_400L // Cache for one day
        val editorService = EditorService.create(
            context = getApplication(),
            configuration = configuration,
            cachePolicy = EditorCachePolicy.MaxAge(cacheIntervalSeconds),
            coroutineScope = viewModelScope
        )
        prepareEditor(editorService)
    }

    fun prepareEditorFromScratch() {
        val configuration = _uiState.value.editorConfiguration ?: return

        val editorService = EditorService.create(
            context = getApplication(),
            configuration = configuration,
            cachePolicy = EditorCachePolicy.Ignore,
            coroutineScope = viewModelScope
        )
        prepareEditor(editorService)
    }

    private fun prepareEditor(editorService: EditorService) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            try {
                val dependencies = editorService.prepare { progress ->
                    _uiState.update { it.copy(loadingProgress = progress.fractionCompleted.toFloat()) }
                }

                _uiState.update {
                    it.copy(
                        editorDependencies = dependencies,
                        isLoading = false,
                        loadingProgress = null
                    )
                }

                countAssetBundles()
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        error = e.message ?: "Unknown error",
                        isLoading = false,
                        loadingProgress = null
                    )
                }
            }
        }
    }

    fun resetEditorCaches() {
        val configuration = _uiState.value.editorConfiguration ?: return

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            try {
                _uiState.update { it.copy(editorDependencies = null) }

                val editorService = EditorService.create(
                    context = getApplication(),
                    configuration = configuration,
                    coroutineScope = viewModelScope
                )
                editorService.purge()

                countAssetBundles()

                _uiState.update { it.copy(isLoading = false) }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        error = e.message ?: "Unknown error",
                        isLoading = false
                    )
                }
            }
        }
    }

    private fun countAssetBundles() {
        viewModelScope.launch {
            try {
                val configuration = _uiState.value.editorConfiguration ?: run {
                    _uiState.update { it.copy(cacheBundleCount = 0) }
                    return@launch
                }

                val editorService = EditorService.create(
                    context = getApplication(),
                    configuration = configuration,
                    coroutineScope = viewModelScope
                )
                val count = editorService.fetchAssetBundleCount()

                _uiState.update { it.copy(cacheBundleCount = count) }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message ?: "Unknown error") }
            }
        }
    }

    private fun createBundledConfiguration(): EditorConfiguration {
        // Bundled offline editor: only the standard `post` type is meaningful.
        _uiState.update {
            it.copy(
                postTypes = listOf(PostTypeDetails.post),
                selectedPostType = PostTypeDetails.post
            )
        }
        return EditorConfiguration.builder(
            siteURL = "https://example.com",
            siteApiRoot = "https://example.com",
            postType = PostTypeDetails.post
        )
            .setPlugins(false)
            .setSiteApiNamespace(arrayOf())
            .setNamespaceExcludedPaths(arrayOf())
            .setAuthHeader("")
            .setCookies(emptyMap())
            .setEnableOfflineMode(true)
            .build()
    }

    private suspend fun loadConfiguration(config: ConfigurationItem.ConfiguredEditor): EditorConfiguration {
        val capabilities = siteCapabilitiesDiscovery.discoverCapabilities(
            siteUrl = config.siteUrl,
            networkAvailabilityProvider = networkAvailabilityProvider
        )

        // For WP.com sites, the stored siteApiRoot is namespace-specific
        // (e.g. https://public-api.wordpress.com/wp/v2/sites/1562023).
        // The editor needs the base REST API root and a siteApiNamespace
        // so the JS middleware can insert the site ID into request paths.
        val wpComSiteId = extractWpComSiteId(config.siteApiRoot)
        val siteApiRoot = if (wpComSiteId != null) {
            "https://public-api.wordpress.com/"
        } else {
            config.siteApiRoot
        }
        val siteApiNamespace = if (wpComSiteId != null) {
            arrayOf("sites/$wpComSiteId/")
        } else {
            arrayOf()
        }

        // Fetch the site's post types. Default the picker to `post` when it's
        // available (the typical case); otherwise pick the first type in the
        // list. Falls back to `PostTypeDetails.post` if the call fails so the
        // editor can still launch with a sensible default.
        val postTypes = loadPostTypes(config) ?: listOf(PostTypeDetails.post)
        val defaultPostType = postTypes.firstOrNull { it.postType == "post" } ?: postTypes.first()
        _uiState.update {
            it.copy(
                postTypes = postTypes,
                selectedPostType = defaultPostType
            )
        }

        return EditorConfiguration.builder(
            siteURL = config.siteUrl,
            siteApiRoot = siteApiRoot,
            postType = defaultPostType
        )
            .setPlugins(capabilities.supportsPlugins)
            .setThemeStyles(capabilities.supportsThemeStyles)
            .setSiteApiNamespace(siteApiNamespace)
            .setNamespaceExcludedPaths(arrayOf())
            .setAuthHeader(config.authHeader)
            .setTitle("")
            .setContent("")
            .setHideTitle(false)
            .setCookies(emptyMap())
            .setEnableNetworkLogging(true)
            .setEnableAssetCaching(capabilities.supportsPlugins)
            .build()
    }

    /**
     * Fetches the site's post types from the WordPress REST API and returns the
     * subset relevant to the editor picker.
     *
     * Mirrors the iOS [SitePreparationView.loadPostTypes] filter:
     * - always include the standard `post` and `page` types
     * - include custom types only when they are `viewable` and have UI visibility
     * - exclude all internal types (`Attachment`, `WpBlock`, etc.)
     *
     * Returns `null` if the post types could not be fetched (e.g. account not
     * found, network error). Callers fall back to a sensible default.
     */
    private suspend fun loadPostTypes(
        config: ConfigurationItem.ConfiguredEditor
    ): List<PostTypeDetails>? {
        val app = getApplication<GutenbergKitApplication>()
        val account = app.accountRepository.all().firstOrNull { it.id() == config.accountId }
            ?: return null
        val client = app.createApiClient(account)

        val result = client.request { builder ->
            builder.postTypes().listWithEditContext()
        }
        if (result !is WpRequestResult.Success) return null

        return result.response.data.postTypes
            .filter { (type, details) ->
                when (type) {
                    is WpPostType.Post, is WpPostType.Page -> true
                    is WpPostType.Custom -> details.viewable && details.visibility.showUi
                    else -> false
                }
            }
            .map { (_, details) ->
                PostTypeDetails(
                    postType = details.slug,
                    restBase = details.restBase,
                    restNamespace = details.restNamespace
                )
            }
            .sortedBy { it.postType }
    }

    /**
     * Extracts the WP.com site ID from a namespace-specific API root URL.
     * Returns null if the URL is not a WP.com API root.
     *
     * Example: "https://public-api.wordpress.com/wp/v2/sites/1562023" -> "1562023"
     */
    private fun extractWpComSiteId(siteApiRoot: String): String? {
        val regex = Regex("""public-api\.wordpress\.com/.+/sites/(\d+)""")
        return regex.find(siteApiRoot)?.groupValues?.get(1)
    }

    fun buildConfiguration(): EditorConfiguration? {
        val baseConfig = _uiState.value.editorConfiguration ?: return null
        val selectedPostType = _uiState.value.selectedPostType ?: return null

        return baseConfig.toBuilder()
            .setEnableNetworkLogging(_uiState.value.enableNetworkLogging)
            .setEnableNativeBlockInserter(_uiState.value.enableNativeInserter)
            .setEnableInserterMediaStrip(_uiState.value.enableInserterMediaStrip)
            .setPostType(selectedPostType)
            .build()
    }
}

class SitePreparationViewModelFactory(
    private val application: Application,
    private val configurationItem: ConfigurationItem
) : ViewModelProvider.Factory {

    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass.isAssignableFrom(SitePreparationViewModel::class.java)) {
            return SitePreparationViewModel(application, configurationItem) as T
        }
        throw IllegalArgumentException("Unknown ViewModel class")
    }
}
