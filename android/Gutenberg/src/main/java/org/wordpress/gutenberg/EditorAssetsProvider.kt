package org.wordpress.gutenberg

import android.webkit.JavascriptInterface
import android.util.Log
import kotlinx.coroutines.runBlocking
import com.google.gson.Gson

class EditorAssetsProvider(private val library: EditorAssetsLibrary) {
    
    companion object {
        private const val TAG = "EditorAssetsProvider"
    }
    
    @JavascriptInterface
    fun loadFetchedEditorAssets(asset: String): String {
        return if (asset == "manifest") {
            try {
                runBlocking {
                    library.manifestContentForEditor()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load manifest", e)
                // Return empty manifest on error
                Gson().toJson(EditorAssetsManifest("", "", emptyList()))
            }
        } else {
            Log.w(TAG, "Unexpected asset requested: $asset")
            "{}"
        }
    }
}