package org.wordpress.gutenberg

/**
 * Sends the editor's requests for the post being edited, and for the paths below it, such as
 * its autosaves, in place of the editor.
 *
 * With a handler, the editor sends none of these requests itself, saves included: a save from
 * the editor, such as the user's or a plugin's call to Gutenberg's `savePost()`, comes here as
 * a write to the post. The editor parses the response as if it had sent the request itself.
 *
 * Set it as [GutenbergView.postRequestHandler] before the editor loads.
 */
fun interface EditorPostRequestHandler {
    /**
     * Sends [request] and returns the server's response as it arrived, error statuses included.
     *
     * Throw only when no response came, such as when the server couldn't be reached. The editor
     * then fails the request as a failed `fetch` does.
     */
    suspend fun perform(request: EditorPostRequest): EditorPostResponse
}

/**
 * A request the editor sends for the post it's editing.
 *
 * @property method The HTTP method, uppercased: `GET`, `PUT` and so on.
 * @property path The REST API path with its query, such as `/wp/v2/posts/1?context=edit`.
 * @property body The JSON body, if the request has one.
 */
class EditorPostRequest(
    val method: String,
    val path: String,
    val body: ByteArray?
)

/**
 * The server's response to an [EditorPostRequest].
 *
 * @property status The HTTP status.
 * @property headers The response's headers.
 * @property body The response's body, as the server sent it.
 */
class EditorPostResponse(
    val status: Int,
    val headers: Map<String, String>,
    val body: ByteArray
)

/**
 * Notified on the main thread when something in the post changes: its content, a setting such
 * as its categories, or a field a plugin adds. Saving the post changes it too.
 *
 * Read the post with [GutenbergView.currentPost].
 */
fun interface EditorPostChangeListener {
    fun onPostChanged()
}
