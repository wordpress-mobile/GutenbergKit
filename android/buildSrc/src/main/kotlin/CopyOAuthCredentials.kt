import org.gradle.api.DefaultTask
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.tasks.InputFile
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction

/**
 * Copies the shared WordPress.com OAuth credentials file into a generated
 * assets directory for the demo app.
 *
 * Modelled as a task with a [DirectoryProperty] output rather than a plain
 * `Copy` so it can be handed to AGP's `sources.assets.addGeneratedSourceDirectory`,
 * which wires the task dependency for us. AGP 9 removed the
 * `applicationVariants`/`mergeAssetsProvider` API the wiring previously used.
 */
abstract class CopyOAuthCredentials : DefaultTask() {
    @get:InputFile
    @get:PathSensitive(PathSensitivity.NAME_ONLY)
    abstract val credentials: RegularFileProperty

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @TaskAction
    fun copy() {
        val source = credentials.get().asFile
        source.copyTo(outputDirectory.get().file(source.name).asFile, overwrite = true)
    }
}
