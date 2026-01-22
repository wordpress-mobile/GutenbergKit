package org.wordpress.gutenberg.model

import java.io.File

/**
 * Helper object to access shared test resources from the iOS test folder.
 */
object TestResources {
    private val resourcesDir: File by lazy {
        // Navigate from android module to the shared iOS test resources
        // Try multiple strategies to find the resources
        val possiblePaths = listOf(
            // When running from android directory
            File(System.getProperty("user.dir"), "../ios/Tests/GutenbergKitTests/Resources"),
            // When running from project root
            File(System.getProperty("user.dir"), "ios/Tests/GutenbergKitTests/Resources"),
            // When running from Gutenberg module directory
            File(System.getProperty("user.dir"), "../../ios/Tests/GutenbergKitTests/Resources")
        )

        possiblePaths.firstOrNull { it.exists() && it.isDirectory }
            ?: throw IllegalStateException(
                "Could not find iOS test resources. Tried: ${possiblePaths.map { it.absolutePath }}"
            )
    }

    fun loadResource(name: String): String {
        val file = File(resourcesDir, name)
        require(file.exists()) { "Test resource not found: ${file.absolutePath}" }
        return file.readText()
    }

    fun resourceExists(name: String): Boolean {
        return File(resourcesDir, name).exists()
    }
}
