/**
 * Retrieves the native-host-provided GBKit object from localStorage or returns
 * an empty object if not found.
 *
 * @returns {Object} The GBKit object.
 */
export function getGBKit() {
	if (window.GBKit) {
		return window.GBKit;
	}

	// Android relies upon "pulling" the GBKit object from the native host, as it
	// does not provide a way to inject JavaScript prior to the WebView loading.
	if (window.editorDelegate) {
		return JSON.parse(window.editorDelegate.getEditorConfiguration());
	}

	const emptyObject = {};
	try {
		return JSON.parse(localStorage.getItem('GBKit')) || emptyObject;
	} catch (error) {
		console.error('Failed parsing GBKit from localStorage:', error);
		return emptyObject;
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
