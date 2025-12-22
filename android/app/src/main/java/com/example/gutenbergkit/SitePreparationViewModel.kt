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
import org.wordpress.gutenberg.services.EditorService

data class SitePreparationUiState(
    val enableNativeInserter: Boolean = true,
    val enableNetworkLogging: Boolean = false,
    val postType: String = "post",
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

    fun startLoading() {
        viewModelScope.launch {
            try {
                val configuration = when (configurationItem) {
                    is ConfigurationItem.BundledEditor -> createBundledConfiguration()
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

    fun setEnableNetworkLogging(enabled: Boolean) {
        _uiState.update { it.copy(enableNetworkLogging = enabled) }
    }

    fun setPostType(postType: String) {
        _uiState.update { it.copy(postType = postType) }
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
        return EditorConfiguration.builder(
            siteURL = "https://example.com",
            siteApiRoot = "https://example.com",
            postType = "post"
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
            siteApiRoot = config.siteApiRoot
        )

        return EditorConfiguration.builder(
            siteURL = config.siteUrl,
            siteApiRoot = config.siteApiRoot,
            postType = _uiState.value.postType
        )
            .setPlugins(capabilities.supportsPlugins)
            .setThemeStyles(capabilities.supportsThemeStyles)
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

    fun buildConfiguration(): EditorConfiguration? {
        val baseConfig = _uiState.value.editorConfiguration ?: return null

        return baseConfig.toBuilder()
            .setEnableNetworkLogging(_uiState.value.enableNetworkLogging)
            // TODO: Add setNativeInserterEnabled when it's available in EditorConfiguration
            .setPostType(_uiState.value.postType)
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
