/**
 * WordPress dependencies
 */
import apiFetch from '@wordpress/api-fetch';
import { getQueryArg } from '@wordpress/url';

/**
 * Internal dependencies
 */
import { getGBKit } from './bridge';

/**
 * @typedef {import('@wordpress/api-fetch').APIFetchMiddleware} APIFetchMiddleware
 */

/**
 * Undo httpV1Middleware's method override at the network level.
 *
 * Gutenberg's built-in httpV1Middleware rewrites PUT/PATCH/DELETE to POST and
 * adds an X-HTTP-Method-Override header.  This is useful for servers that
 * reject non-POST methods, but the header is not in the CORS allow-list for
 * many WordPress hosts (including WordPress.com), so cross-origin preflight
 * requests fail.
 *
 * Because httpV1Middleware runs *after* all custom apiFetch middleware (which
 * can only be prepended), we intercept at the globalThis.fetch level — the
 * last stop before the network — and restore the original HTTP method.
 */
function installHttpMethodOverrideFix() {
	const nativeFetch = globalThis.fetch;
	globalThis.fetch = function ( input, init ) {
		if ( init?.headers?.[ 'X-HTTP-Method-Override' ] ) {
			init = {
				...init,
				method: init.headers[ 'X-HTTP-Method-Override' ],
			};
			const { 'X-HTTP-Method-Override': _override, ...headers } =
				init.headers;
			init.headers = headers;
		}
		return nativeFetch.call( this, input, init );
	};
}

/**
 * Initializes the API fetch configuration and middleware.
 *
 * @return {void}
 */
export function configureApiFetch() {
	installHttpMethodOverrideFix();
	const { siteApiRoot = '', preloadData = null } = getGBKit();

	apiFetch.use( apiFetch.createRootURLMiddleware( siteApiRoot ) );
	apiFetch.use( corsMiddleware );
	apiFetch.use( apiPathModifierMiddleware );
	apiFetch.use( tokenAuthMiddleware );
	apiFetch.use( mediaUploadMiddleware );
	apiFetch.use( transformOEmbedApiResponse );
	apiFetch.use(
		apiFetch.createPreloadingMiddleware( preloadData ?? defaultPreloadData )
	);
}

/**
 * Middleware setting the CORS mode and remove a specific header causing CORS errors.
 *
 * @type {APIFetchMiddleware}
 *
 * @todo Address the CORS header hack.
 */
function corsMiddleware( options, next ) {
	options.mode = 'cors';

	// HACK: This custom header causes CORS errors. Although settings the mode to
	// 'cors' should prevent this header, incorrect middleware order results in
	// setting the header.
	// https://github.com/Automattic/jetpack/blob/7801b7f21e01d8a4a102c44dac69c6ebdd1e549d/projects/plugins/jetpack/extensions/editor.js#L22-L52
	if ( options.headers ) {
		delete options.headers[ 'x-wp-api-fetch-from-editor' ];
	}

	return next( options );
}

/**
 * Middleware modifying the API path by inserting the site API namespace.
 *
 * @type {APIFetchMiddleware}
 */
function apiPathModifierMiddleware( options, next ) {
	const { siteApiNamespace, namespaceExcludedPaths } = getGBKit();
	const namespaceRegex = new RegExp( `(${ siteApiNamespace.join( '|' ) })` );
	const isEligiblePath =
		options.path &&
		! namespaceExcludedPaths.some( ( path ) =>
			options.path.startsWith( path )
		);

	const alreadyHasSiteNamespace =
		namespaceRegex.test( options.path ) ||
		/\/sites\/[^/]+\//.test( options.path );

	if ( isEligiblePath && ! alreadyHasSiteNamespace ) {
		// Insert the API namespace after the first two path segments.
		options.path = options.path.replace(
			/^(?<apiPath>\/?(?:[\w.-]+\/){2})/,
			`$<apiPath>${ siteApiNamespace[ 0 ] }`
		);
	}

	return next( options );
}

/**
 * Middleware that handles token-based authentication.
 *
 * When an auth header is present, this middleware:
 * 1. Adds the Authorization header to the request
 * 2. Sets credentials to 'omit' to prevent cookies from interfering with token authentication
 *
 * This prevents authentication conflicts where browser cookies could disrupt
 * token-based authentication by being sent alongside the Authorization header.
 *
 * @type {APIFetchMiddleware}
 */
function tokenAuthMiddleware( options, next ) {
	const { authHeader } = getGBKit();
	options.headers = options.headers || {};

	if ( authHeader ) {
		options.headers.Authorization = authHeader;
		options.credentials = 'omit'; // Avoid cookies disrupting token authentication
	}

	return next( options );
}

/**
 * Middleware to modify media upload requests.
 *
 * This middleware intercepts requests to the media endpoint and conditionally
 * removes the 'post' field if its value is '-1', which is used for draft posts.
 *
 * @type {APIFetchMiddleware}
 */
function mediaUploadMiddleware( options, next ) {
	if (
		options.path &&
		options.path.startsWith( '/wp/v2/media' ) &&
		options.method === 'POST' &&
		options.body instanceof FormData &&
		options.body.get( 'post' ) === '-1'
	) {
		options.body.delete( 'post' );
	}

	return next( options );
}

/**
 * Remove the wrapping element from the oEmbed response, as it breaks
 * Gutenberg's sizing styles.
 *
 * @type {APIFetchMiddleware}
 *
 * @todo Hoist this host-specific logic to the host app.
 */
function transformOEmbedApiResponse( options, next ) {
	if ( options.path && options.path.indexOf( 'oembed' ) !== -1 ) {
		const url = getQueryArg( options.path, 'url' );
		const response = next( options, next );

		/**
		 * Creates an embed response emulating core's fallback link.
		 */
		function createFallbackResponse() {
			const link = document.createElement( 'a' );
			link.href = url;
			link.innerText = url;
			return {
				html: link.outerHTML,
				type: 'rich',
				provider_name: 'Embed',
			};
		}

		return new Promise( ( resolve ) => {
			response
				.then( ( data ) => {
					if ( data.html ) {
						/**
						 * Removes wrappers from YouTube, Vimeo, Dailymotion, TED block, e.g.
						 * <span class="embed-youtube">, <div class="embed-vimeo">, <div class="embed-dailymotion">, <div class="embed-ted">
						 * and return just the <iframe> child directly to allow wide & full width sizing.
						 */
						const doc =
							document.implementation.createHTMLDocument( '' );
						doc.body.innerHTML = data.html;
						const selectors = [
							'[class="embed-youtube"]',
							'[class="embed-vimeo"]',
							'[class="embed-dailymotion"]',
							'[class="embed-ted"]',
						].join( ',' );
						const wrapper = doc.querySelector( selectors );
						data.html = wrapper ? wrapper.innerHTML : data.html;
					}

					resolve( data );
				} )
				.catch( () => {
					resolve( createFallbackResponse() );
				} );
		} );
	}

	return next( options, next );
}

const defaultPreloadData = {
	'/wp/v2/types?context=view': {
		body: {
			post: {
				description: '',
				hierarchical: false,
				has_archive: false,
				name: 'Posts',
				slug: 'post',
				taxonomies: [ 'category', 'post_tag' ],
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
			taxonomies: [ 'category', 'post_tag' ],
			rest_base: 'posts',
			rest_namespace: 'wp/v2',
			template: [],
			template_lock: false,
		},
	},
};
