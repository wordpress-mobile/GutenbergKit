package org.wordpress.gutenberg.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Payload delivered to the host app when the web editor requests the native
 * block inserter. Mirrors the shape produced by
 * `preprocessBlockTypesForNativeInserter` in `src/utils/blocks.js` and the
 * `BlockInserterBridge` component at `src/components/native-inserter/index.jsx`.
 */
@Serializable
data class BlockInserterPayload(
    val sections: List<BlockInserterSection> = emptyList(),
    val patterns: List<BlockPattern> = emptyList(),
    val patternCategories: List<BlockPatternCategory> = emptyList(),
    val sourceRect: SourceRect? = null,
) {
    companion object {
        private val json = Json {
            ignoreUnknownKeys = true
            isLenient = true
        }

        fun fromJson(jsonString: String): BlockInserterPayload =
            json.decodeFromString(serializer(), jsonString)
    }
}

@Serializable
data class BlockInserterSection(
    /** Stable category slug. Synthetic sections use `gbk-`-prefixed values (e.g. `gbk-most-used`). */
    val category: String = "gbk-missing-category",
    /** Localized display name. Null for synthetic sections that the host renders without a header. */
    val name: String? = null,
    val blocks: List<BlockType> = emptyList(),
)

@Serializable
data class BlockType(
    /**
     * Unique identifier for this block variant. NOT the same as [name] — multiple
     * entries can share a `name` but have different `id` values to represent
     * variants with different initial attributes (e.g. `core/embed/youtube`).
     */
    val id: String,
    val name: String,
    val title: String? = null,
    val description: String? = null,
    val category: String? = null,
    val keywords: List<String> = emptyList(),
    /** SVG markup as a string, or null when the block has no renderable icon. */
    val icon: String? = null,
    /**
     * Brand colour declared by the block's icon metadata (e.g. Pocket Casts red).
     * The web editor applies this as CSS `color`, which paths inside the SVG
     * pick up via `currentColor`. Null for icons that rely on a theme tint.
     */
    val iconForeground: String? = null,
    val frecency: Double = 0.0,
    val isDisabled: Boolean = false,
    val isSearchOnly: Boolean = false,
    val parents: List<String> = emptyList(),
)

@Serializable
data class BlockPattern(
    val name: String,
    val title: String,
    /** HTML with Gutenberg block delimiters. */
    val content: String,
    val blockTypes: List<String> = emptyList(),
    val categories: List<String> = emptyList(),
    val description: String? = null,
    val keywords: List<String> = emptyList(),
    val source: String? = null,
    val viewportWidth: Int? = null,
)

@Serializable
data class BlockPatternCategory(
    /** Category slug (e.g. `gallery`). */
    val name: String,
    /** Localized display label. */
    val label: String,
)

/**
 * Position of the UI element that triggered the inserter, in CSS pixels relative
 * to the WebView. Host apps can use this to anchor a popover on tablets.
 */
@Serializable
data class SourceRect(
    val x: Double = 0.0,
    val y: Double = 0.0,
    val width: Double = 0.0,
    val height: Double = 0.0,
)
