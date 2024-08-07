/**
 * WordPress dependencies
 */
import apiFetch from '@wordpress/api-fetch';

/**
 * Initializes the API fetch configuration and middleware.
 *
 * This function sets up the root URL middleware, adds headers to requests,
 * and preloads some endpoints with mock data for specific components.
 */
export function initializeApiFetch() {
	apiFetch.use(apiFetch.createRootURLMiddleware(''));

	apiFetch.use((options, next) => {
		options.headers = options.headers || new Headers();
		options.headers.set('Content-Type', 'application/json');

		return next({
			...options,
			headers: {
				Authorization: 'Basic ',
			},
		});
	});

	// Preload some endpoints to return data needed for some components
	// Like PostTitle.
	const LOCAL_POST_ID = 1;
	const LOCAL_AUTHOR_ID = 1;

	apiFetch.use(
		apiFetch.createPreloadingMiddleware({
			'/wp/v2/types?context=view': {
				body: {
					post: {
						description: '',
						hierarchical: false,
						has_archive: false,
						name: 'Posts',
						slug: 'post',
						taxonomies: ['category', 'post_tag'],
						rest_base: 'posts',
						rest_namespace: 'wp/v2',
						template: [],
						template_lock: false,
						_links: {},
					},
					page: {
						description: '',
						hierarchical: true,
						has_archive: false,
						name: 'Pages',
						slug: 'page',
						taxonomies: [],
						rest_base: 'pages',
						rest_namespace: 'wp/v2',
						template: [],
						template_lock: false,
						_links: {},
					},
				},
			},
			'/wp/v2/types/post?context=edit': {
				body: {
					name: 'Posts',
					slug: 'post',
					supports: {
						title: true,
						editor: true,
						author: true,
						thumbnail: true,
						excerpt: true,
						trackbacks: true,
						'custom-fields': true,
						comments: true,
						revisions: true,
						'post-formats': true,
						autosave: true,
					},
					taxonomies: ['category', 'post_tag'],
					rest_base: 'posts',
					rest_namespace: 'wp/v2',
					template: [],
					template_lock: false,
				},
			},
			[`/wp/v2/posts/${LOCAL_POST_ID}?context=edit`]: {
				body: {
					id: LOCAL_POST_ID,
					slug: '',
					status: 'auto-draft',
					type: 'post',
					title: { raw: 'Auto Draft', rendered: 'Auto Draft' },
					content: {
						raw: '',
						rendered: '',
						protected: false,
						block_version: 0,
					},
					excerpt: { raw: '', rendered: '', protected: false },
					author: LOCAL_AUTHOR_ID,
					featured_media: 0,
				},
			},
		})
	);
}
