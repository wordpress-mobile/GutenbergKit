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
			type: post?.type ?? 'post',
		};
	}

	return {
		type: 'post',
		status: 'draft',
	};
}
