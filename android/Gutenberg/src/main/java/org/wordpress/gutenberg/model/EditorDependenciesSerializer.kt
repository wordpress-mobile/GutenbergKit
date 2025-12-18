package org.wordpress.gutenberg.model

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.util.UUID

/**
 * Handles serialization of [EditorDependencies] to and from disk.
 *
 * Since [EditorDependencies] contains non-serializable types like [File],
 * this class provides methods to serialize dependencies to a temporary file
 * and deserialize them back. This is useful for passing large dependency
 * objects between activities without exceeding Intent size limits.
 *
 * ## Usage
 *
 * ```kotlin
 * // In the sending activity:
 * val filePath = EditorDependenciesSerializer.writeToDisk(context, dependencies)
 * intent.putExtra("dependencies_path", filePath)
 *
 * // In the receiving activity:
 * val filePath = intent.getStringExtra("dependencies_path")
 * val dependencies = EditorDependenciesSerializer.readFromDisk(filePath)
 * ```
 */
object EditorDependenciesSerializer {
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    /**
     * Serializable representation of [EditorDependencies].
     *
     * This class mirrors [EditorDependencies] but with serializable types:
     * - [File] references are stored as path strings
     * - [Date] objects are stored as Unix timestamps
     */
    @Serializable
    private data class SerializedDependencies(
        val editorSettings: EditorSettings,
        val assetBundleRaw: EditorAssetBundle.RawAssetBundle,
        val assetBundleRootPath: String,
        val preloadList: EditorPreloadList?
    )

    /**
     * Writes [EditorDependencies] to a temporary file in the app's cache directory.
     *
     * @param context The Android context.
     * @param dependencies The dependencies to serialize.
     * @return The absolute path to the created file.
     */
    fun writeToDisk(context: Context, dependencies: EditorDependencies): String {
        val serialized = SerializedDependencies(
            editorSettings = dependencies.editorSettings,
            assetBundleRaw = EditorAssetBundle.RawAssetBundle(
                manifest = dependencies.assetBundle.manifest,
                downloadDate = dependencies.assetBundle.downloadDate
            ),
            assetBundleRootPath = dependencies.assetBundle.bundleRoot.absolutePath,
            preloadList = dependencies.preloadList
        )

        val fileName = "editor_dependencies_${UUID.randomUUID()}.json"
        val file = File(context.cacheDir, fileName)
        file.writeText(json.encodeToString(serialized))

        return file.absolutePath
    }

    /**
     * Reads [EditorDependencies] from a file and deletes the file.
     *
     * @param filePath The absolute path to the serialized dependencies file.
     * @return The deserialized dependencies, or `null` if the file doesn't exist or is invalid.
     */
    fun readFromDisk(filePath: String?): EditorDependencies? {
        if (filePath == null) return null

        val file = File(filePath)
        if (!file.exists()) return null

        return try {
            val data = file.readText()
            val serialized = json.decodeFromString<SerializedDependencies>(data)

            val dependencies = EditorDependencies(
                editorSettings = serialized.editorSettings,
                assetBundle = serialized.assetBundleRaw.toEditorAssetBundle(
                    File(serialized.assetBundleRootPath)
                ),
                preloadList = serialized.preloadList
            )

            // Clean up the temp file
            file.delete()

            dependencies
        } catch (e: Exception) {
            file.delete()
            null
        }
    }
}
