package org.wordpress.gutenberg

import com.google.gson.annotations.SerializedName
import org.jsoup.Jsoup

data class EditorAssetsManifest(
    @SerializedName("scripts")
    val scripts: String,
    @SerializedName("styles") 
    val styles: String,
    @SerializedName("allowed_block_types")
    val allowedBlockTypes: List<String>
) {
    fun parseAssetLinks(defaultScheme: String?): List<String> {
        val html = """
            <html>
                <head>
                $scripts
                $styles
                </head>
                <body></body>
            </html>
        """.trimIndent()

        val document = Jsoup.parse(html)
        val assetLinks = mutableListOf<String>()

        // Extract script sources
        document.select("script[src]").forEach { element ->
            val src = element.attr("src")
            assetLinks.add(resolveAssetLink(src, defaultScheme))
        }

        // Extract stylesheet hrefs
        document.select("link[rel=stylesheet][href]").forEach { element ->
            val href = element.attr("href")
            assetLinks.add(resolveAssetLink(href, defaultScheme))
        }

        return assetLinks
    }

    private fun resolveAssetLink(link: String, defaultScheme: String?): String {
        return when {
            link.startsWith("//") -> "${defaultScheme ?: "https"}:$link"
            else -> link
        }
    }
}
