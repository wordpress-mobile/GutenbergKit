/**
 * Notifies the native host that the editor has loaded.
 *
 * @return {void}
 */
export function editorLoaded() {
	if (window.editorDelegate) {
		window.editorDelegate.onEditorLoaded();
	}

	if (window.webkit) {
		window.webkit.messageHandlers.editorDelegate.postMessage({
			message: 'onEditorLoaded',
			body: {},
		});
	}
}

/**
 * Notifies the native host that the editor content has changed.
 *
 * @return {void}
 */
export function onEditorContentChanged() {
	if (window.editorDelegate) {
		window.editorDelegate.onEditorContentChanged();
	}

	if (window.webkit) {
		window.webkit.messageHandlers.editorDelegate.postMessage({
			message: 'onEditorContentChanged',
		});
	}
}

/**
 * Notifies the native host that the editor history stack has changed.
 *
 * @param {boolean} hasUndo Whether the editor has undo history.
 * @param {boolean} hasRedo Whether the editor has redo history.
 *
 * @return {void}
 */
export function onEditorHistoryChanged(hasUndo, hasRedo) {
	if (window.editorDelegate) {
		window.editorDelegate.onEditorHistoryChanged(hasUndo, hasRedo);
	}

	if (window.webkit) {
		window.webkit.messageHandlers.editorDelegate.postMessage({
			message: 'onEditorHistoryChanged',
			body: { hasUndo, hasRedo },
		});
	}
}

/**
 * Notifies the native host that blocks have changed.
 *
 * @param {boolean} [isEmpty=false] Whether the editor is empty.
 *
 * @return {void}
 */
export function onBlocksChanged(isEmpty = false) {
	if (window.editorDelegate) {
		window.editorDelegate.onBlocksChanged(isEmpty);
	}

	if (window.webkit) {
		window.webkit.messageHandlers.editorDelegate.postMessage({
			message: 'onBlocksChanged',
			body: { isEmpty },
		});
	}
}

/**
 * Requests the native host to show the block picker.
 *
 * @return {void}
 */
export function showBlockPicker() {
	if (window.editorDelegate) {
		window.editorDelegate.showBlockPicker();
	}

	if (window.webkit) {
		window.webkit.messageHandlers.editorDelegate.postMessage({
			message: 'showBlockPicker',
			body: {},
		});
	}
}

/**
 * Requests the native host to open the Media Library
 *
 * @param {import('../hooks/use-media-upload').MediaUploadConfig} config Media Library configuration.
 *
 * @return {void}
 */
export function openMediaLibrary(config) {
	if (window.editorDelegate) {
		window.editorDelegate.openMediaLibrary(JSON.stringify(config));
	}

	if (window.webkit) {
		window.webkit.messageHandlers.editorDelegate.postMessage({
			message: 'openMediaLibrary',
			body: config,
		});
	}
}

/**
 * Retrieves the native-host-provided GBKit object from localStorage or returns
 * an empty object if not found.
 *
 * @return {Object} The GBKit object.
 */
export function getGBKit() {
	if (window.GBKit) {
		return window.GBKit;
	}

	// Android relies upon "pulling" the GBKit object from the native host, as it
	// does not provide a way to inject JavaScript prior to the WebView loading.
	if (window.editorDelegate) {
		try {
			return JSON.parse(window.editorDelegate.getEditorConfiguration());
		} catch (error) {
			return {};
		}
	}

	try {
		return JSON.parse(localStorage.getItem('GBKit')) || {};
	} catch (error) {
		return {};
	}
}

/**
 * @typedef {Object} Post
 * @property {string} [title]   The title of the post.
 * @property {string} [content] The content of the post.
 * @property {string} type      The type of the post.
 * @property {number} id        The ID of the post.
 * @property {number} [author]  The author ID of the post.
 * @property {string} [status]  The status of the post.
 */

/**
 * Retrieves the current post data from the GBKit global.
 *
 * @return {Post} The post object containing the following properties:
 */
export function getPost() {
	const { post } = getGBKit();
	if (post) {
		return {
			id: post.id,
			title: { raw: decodeURIComponent(post.title) },
			content: { raw: decodeURIComponent(post.content) },
			type: post.type || 'post',
		};
	}

	// Since we don't use the auto-save functionality, draft posts need to have an ID.
	// We assign a temporary ID of -1.
	return {
		type: 'post',
		status: 'draft',
		id: -1,
	};
}

/**
 * Logs an error to the host app.
 *
 * @param {Error} error - The error object to be logged.
 */
export function logError(error) {
	if (window.editorDelegate) {
		window.editorDelegate.logError(error);
	}

	if (window.webkit) {
		window.webkit.messageHandlers.editorDelegate.postMessage({
			message: 'logError',
			body: { error: error.message },
		});
	}
}
