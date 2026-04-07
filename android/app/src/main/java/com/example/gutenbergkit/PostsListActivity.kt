package com.example.gutenbergkit

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.example.gutenbergkit.ui.theme.AppTheme
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import org.wordpress.gutenberg.model.EditorConfiguration
import org.wordpress.gutenberg.model.EditorDependencies
import org.wordpress.gutenberg.model.EditorDependenciesSerializer
import org.wordpress.gutenberg.model.PostTypeDetails
import rs.wordpress.api.kotlin.WpRequestResult
import uniffi.wp_api.AnyPostWithEditContext
import uniffi.wp_api.PostEndpointType
import uniffi.wp_api.PostListParams
import uniffi.wp_api.PostStatus

/**
 * Lists posts from a WordPress site so the user can pick one to edit.
 *
 * Receives an [EditorConfiguration] (already prepared) and an account ID via Intent extras,
 * fetches posts via the WordPress REST API using [WpApiClient], and on selection launches
 * [EditorActivity] with the post's title, content, and ID.
 */
class PostsListActivity : ComponentActivity() {

    companion object {
        const val EXTRA_ACCOUNT_ID = "account_id"
        const val EXTRA_POST_TYPE = "post_type"

        fun createIntent(
            context: Context,
            accountId: ULong,
            postType: PostTypeDetails,
            configuration: EditorConfiguration,
            dependencies: EditorDependencies?
        ): Intent {
            return Intent(context, PostsListActivity::class.java).apply {
                putExtra(EXTRA_ACCOUNT_ID, accountId.toLong())
                putExtra(EXTRA_POST_TYPE, postType)
                putExtra(MainActivity.EXTRA_CONFIGURATION, configuration)
                if (dependencies != null) {
                    val filePath = EditorDependenciesSerializer.writeToDisk(context, dependencies)
                    putExtra(EditorActivity.EXTRA_DEPENDENCIES_PATH, filePath)
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val accountId = intent.getLongExtra(EXTRA_ACCOUNT_ID, -1L).takeIf { it >= 0 }?.toULong()
        val postType = intent.getParcelableExtra(EXTRA_POST_TYPE, PostTypeDetails::class.java)
            ?: PostTypeDetails.post
        val configuration = intent.getParcelableExtra(MainActivity.EXTRA_CONFIGURATION, EditorConfiguration::class.java)
        val dependenciesPath = intent.getStringExtra(EditorActivity.EXTRA_DEPENDENCIES_PATH)

        if (accountId == null || configuration == null) {
            finish()
            return
        }

        val viewModel = ViewModelProvider(
            this,
            PostsListViewModelFactory(application, accountId, postType)
        )[PostsListViewModel::class.java]

        setContent {
            AppTheme {
                PostsListScreen(
                    viewModel = viewModel,
                    onClose = { finish() },
                    onPostSelected = { post ->
                        launchEditor(post, configuration, dependenciesPath, accountId)
                    }
                )
            }
        }
    }

    private fun launchEditor(
        post: AnyPostWithEditContext,
        baseConfiguration: EditorConfiguration,
        dependenciesPath: String?,
        accountId: ULong
    ) {
        val updatedConfig = baseConfiguration.toBuilder()
            .setPostId(post.id.toUInt())
            .setTitle(post.title?.raw ?: "")
            .setContent(post.content.raw ?: "")
            .build()

        val intent = Intent(this, EditorActivity::class.java).apply {
            putExtra(MainActivity.EXTRA_CONFIGURATION, updatedConfig)
            putExtra(EditorActivity.EXTRA_ACCOUNT_ID, accountId.toLong())
            if (dependenciesPath != null) {
                putExtra(EditorActivity.EXTRA_DEPENDENCIES_PATH, dependenciesPath)
            }
        }
        startActivity(intent)
    }
}

data class PostsListUiState(
    val posts: List<AnyPostWithEditContext> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null
)

class PostsListViewModel(
    application: android.app.Application,
    private val accountId: ULong,
    private val postType: PostTypeDetails
) : AndroidViewModel(application) {

    private val _uiState = MutableStateFlow(PostsListUiState())
    val uiState: StateFlow<PostsListUiState> = _uiState.asStateFlow()

    fun loadPosts() {
        if (_uiState.value.isLoading) return

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null, posts = emptyList()) }

            try {
                val app = getApplication<GutenbergKitApplication>()
                val account = app.accountRepository.all().firstOrNull { it.id() == accountId }
                    ?: throw IllegalStateException("Account not found")
                val client = app.createApiClient(account)

                val endpointType = when (postType.postType) {
                    "page" -> PostEndpointType.Pages
                    "post" -> PostEndpointType.Posts
                    else -> PostEndpointType.Custom(postType.postType)
                }

                val all = mutableListOf<AnyPostWithEditContext>()
                var page = 1u
                val perPage = 20u
                while (true) {
                    val params = PostListParams(
                        page = page,
                        perPage = perPage,
                        status = listOf(PostStatus.Any)
                    )
                    val result = client.request { builder ->
                        builder.posts().listWithEditContext(endpointType, params)
                    }
                    when (result) {
                        is WpRequestResult.Success -> {
                            val data = result.response.data
                            all.addAll(data)
                            if (data.size < perPage.toInt()) break
                            page++
                        }
                        else -> {
                            throw IllegalStateException("Failed to load posts: $result")
                        }
                    }
                }

                _uiState.update { it.copy(posts = all, isLoading = false) }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message ?: "Unknown error", isLoading = false) }
            }
        }
    }
}

class PostsListViewModelFactory(
    private val application: android.app.Application,
    private val accountId: ULong,
    private val postType: PostTypeDetails
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass.isAssignableFrom(PostsListViewModel::class.java)) {
            return PostsListViewModel(application, accountId, postType) as T
        }
        throw IllegalArgumentException("Unknown ViewModel class")
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PostsListScreen(
    viewModel: PostsListViewModel,
    onClose: () -> Unit,
    onPostSelected: (AnyPostWithEditContext) -> Unit
) {
    val uiState by viewModel.uiState.collectAsState()

    LaunchedEffect(Unit) {
        viewModel.loadPosts()
    }

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text("Posts") },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back"
                        )
                    }
                }
            )
        }
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            when {
                uiState.isLoading && uiState.posts.isEmpty() -> {
                    CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                }
                uiState.error != null -> {
                    Column(
                        modifier = Modifier
                            .align(Alignment.Center)
                            .padding(16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            "Error loading posts",
                            style = MaterialTheme.typography.titleMedium
                        )
                        Text(
                            uiState.error ?: "",
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }
                uiState.posts.isEmpty() -> {
                    Text(
                        "No posts found",
                        modifier = Modifier.align(Alignment.Center)
                    )
                }
                else -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(vertical = 8.dp)
                    ) {
                        items(uiState.posts, key = { it.id }) { post ->
                            PostRow(post = post, onClick = { onPostSelected(post) })
                            HorizontalDivider()
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PostRow(post: AnyPostWithEditContext, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        val title = post.title?.rendered?.ifBlank { "(no title)" } ?: "(no title)"
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        val excerpt = post.excerpt?.rendered?.stripHtml().orEmpty()
        if (excerpt.isNotBlank()) {
            Text(
                text = excerpt,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

private fun String.stripHtml(): String =
    this.replace(Regex("<[^>]+>"), "").trim()
