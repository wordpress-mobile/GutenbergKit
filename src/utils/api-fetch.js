/**
 * WordPress dependencies
 */
import apiFetch from '@wordpress/api-fetch';
import { getQueryArg } from '@wordpress/url';

/**
 * Internal dependencies
 */
import { getGBKit } from './bridge';
import { info, error as logError } from './logger';

/**
 * @typedef {import('@wordpress/api-fetch').APIFetchMiddleware} APIFetchMiddleware
 */

/** Matches `POST /wp/v2/media` but not sub-paths like `/wp/v2/media/123`. */
const MEDIA_UPLOAD_PATH = /^\/wp\/v2\/media(\?|$)/;

/**
 * Initializes the API fetch configuration and middleware.
 *
 * @return {void}
 */
export function configureApiFetch() {
	const { siteApiRoot = '', preloadData = null } = getGBKit();

	apiFetch.use( apiFetch.createRootURLMiddleware( siteApiRoot ) );
	apiFetch.use( corsMiddleware );
	apiFetch.use( apiPathModifierMiddleware );
	apiFetch.use( tokenAuthMiddleware );
	apiFetch.use( filterEndpointsMiddleware );
	apiFetch.use( nativeMediaUploadMiddleware );
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
	delete options.headers[ 'x-wp-api-fetch-from-editor' ];

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

	if ( isEligiblePath && ! namespaceRegex.test( options.path ) ) {
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
 * Middleware to filter out requests to specific endpoints.
 *
 * @type {APIFetchMiddleware}
 */
function filterEndpointsMiddleware( options, next ) {
	const { post } = getGBKit();
	const { id, restNamespace, restBase } = post ?? {};

	if ( id === undefined || ! restNamespace || ! restBase ) {
		return next( options );
	}

	const disabledPath = `/${ restNamespace }/${ restBase }/${ id }`;

	if (
		options.path === disabledPath ||
		options.path?.startsWith( `${ disabledPath }?` )
	) {
		return Promise.resolve( [] );
	}
	return next( options );
}

/**
 * Middleware that routes media uploads through the native host's local HTTP
 * server for processing (e.g. image resizing) before uploading to WordPress.
 *
 * Exported for testing only.
 *
 * When `nativeUploadPort` is configured in GBKit, this middleware intercepts
 * `POST /wp/v2/media` requests, forwards the file to the native server, and
 * returns the response in WordPress REST API attachment format so the existing
 * Gutenberg upload pipeline (blob previews, save locking, entity caching)
 * works unchanged.
 *
 * When the native server is not configured, requests pass through unmodified.
 *
 * Note: Ideally, media uploads would be handled via the `mediaUpload` editor
 * setting (see the Gutenberg Framework guides), but GutenbergKit uses
 * Gutenberg's `EditorProvider` which overwrites that setting internally:
 * https://github.com/WordPress/gutenberg/blob/29914e1d09a344edce58d938fa4992e1ec248e41/packages/editor/src/components/provider/use-block-editor-settings.js#L340
 *
 * Until GutenbergKit is refactored to use `BlockEditorProvider` and aligns
 * with the Gutenberg Framework guides (https://wordpress.org/gutenberg-framework/docs/intro/),
 * this api-fetch middleware approach is necessary. For context, see:
 * - https://github.com/wordpress-mobile/GutenbergKit/pull/24
 * - https://github.com/wordpress-mobile/GutenbergKit/pull/50
 * - https://github.com/wordpress-mobile/GutenbergKit/pull/108
 *
 * @type {APIFetchMiddleware}
 */
export function nativeMediaUploadMiddleware( options, next ) {
	const { nativeUploadPort, nativeUploadToken } = getGBKit();

	if (
		! nativeUploadPort ||
		! options.method ||
		options.method.toUpperCase() !== 'POST' ||
		! options.path ||
		! MEDIA_UPLOAD_PATH.test( options.path ) ||
		! ( options.body instanceof FormData )
	) {
		return next( options );
	}

	const file = options.body.get( 'file' );
	if ( ! file ) {
		return next( options );
	}

	info(
		`Routing upload of ${ file.name } through native server on port ${ nativeUploadPort }`
	);

	const formData = new FormData();
	formData.append( 'file', file, file.name );

	return fetch( `http://localhost:${ nativeUploadPort }/upload`, {
		method: 'POST',
		headers: {
			Authorization: `Bearer ${ nativeUploadToken }`,
		},
		body: formData,
		signal: options.signal,
	} )
		.then( ( response ) => {
			if ( ! response.ok ) {
				return response.text().then( ( body ) => {
					const message =
						response.status === 413
							? `The file is too large to upload. Please choose a smaller file.`
							: `Native upload failed (${ response.status }): ${
									body || response.statusText
							  }`;
					const error = new Error( message );
					error.code =
						response.status === 413
							? 'upload_file_too_large'
							: 'upload_failed';
					throw error;
				} );
			}
			return response.json();
		} )
		.then( ( result ) => {
			// Transform native server response into WordPress REST API
			// attachment shape expected by @wordpress/media-utils.
			return {
				id: result.id,
				source_url: result.url,
				alt_text: result.alt || '',
				caption: {
					raw: result.caption || '',
					rendered: result.caption || '',
				},
				title: {
					raw: result.title || '',
					rendered: result.title || '',
				},
				mime_type: result.mime,
				media_type: result.type,
				link: result.url,
			};
		} )
		.catch( ( err ) => {
			logError( 'Native upload failed', err );
			throw err;
		} );
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
		MEDIA_UPLOAD_PATH.test( options.path ) &&
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
