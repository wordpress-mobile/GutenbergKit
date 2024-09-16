/**
 * WordPress dependencies
 */
import apiFetch from '@wordpress/api-fetch';

/**
 * Internal dependencies
 */
import { getGBKit } from './store';

/**
 * Initializes the API fetch configuration and middleware.
 *
 * This function sets up the root URL middleware, adds headers to requests,
 * and preloads some endpoints with mock data for specific components.
 */
export function initializeApiFetch() {
	const { siteApiRoot, authHeader } = getGBKit();

	apiFetch.use(apiFetch.createRootURLMiddleware(siteApiRoot));
	apiFetch.use(corsMiddleware);
	apiFetch.use(apiPathModifierMiddleware);
	apiFetch.use(createHeadersMiddleware(authHeader));
	apiFetch.use(filterEndpointsMiddleware);

	// Preload some endpoints to return data needed for some components
	// Like PostTitle.
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
		})
	);
}

function corsMiddleware(options, next) {
	options.mode = 'cors';

	// TODO: Ensure this header is not set via CORS mode.
	// This custom header causes CORS errors. Although settings the mode to 'cors'
	// should prevent this header, incorrect middleware order results in setting
	// the header.
	// https://github.com/Automattic/jetpack/blob/7801b7f21e01d8a4a102c44dac69c6ebdd1e549d/projects/plugins/jetpack/extensions/editor.js#L22-L52
	delete options.headers['x-wp-api-fetch-from-editor'];

	return next(options);
}

function apiPathModifierMiddleware(options, next) {
	const { siteApiNamespace } = getGBKit();

	if (
		options.path &&
		siteApiNamespace &&
		!options.path.includes(siteApiNamespace)
	) {
		// Insert the API namespace after the first two path segments.
		options.path = options.path.replace(
			/^(?<apiPath>\/?(?:[\w.-]+\/){2})/,
			`$<apiPath>${siteApiNamespace}/`
		);
	}
	return next(options);
}

function createHeadersMiddleware(authHeader) {
	return (options, next) => {
		options.headers = options.headers || {};

		if (authHeader) {
			options.headers.Authorization = authHeader;
		}

		return next(options);
	};
}

function filterEndpointsMiddleware(options, next) {
	const disabledEndpoints = [
		/^\/wp\/v2\/posts\/-?\d+/, // Matches /wp/v2/posts/{ID}
		/^\/wp\/v2\/pages\/-?\d+/, // Matches /wp/v2/pages/{ID}
	];
	const isDisabled = disabledEndpoints.some((pattern) =>
		pattern.test(options.path)
	);

	if (isDisabled) {
		return Promise.resolve([]);
	}
	return next(options);
}
