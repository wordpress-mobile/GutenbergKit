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
