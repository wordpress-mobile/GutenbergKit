/**
 * Internal dependencies
 */
import { onNetworkRequest, getGBKit } from './bridge';
import { debug } from './logger';

/**
 * Initializes the global fetch interceptor.
 * Wraps window.fetch to log all network requests and responses.
 * Only overrides window.fetch if network logging is enabled in config.
 *
 * @return {void}
 */
export function initializeFetchInterceptor() {
	// Don't initialize if already done
	if ( window.__fetchInterceptorInitialized ) {
		return;
	}

	const config = getGBKit();

	// Only override window.fetch if network logging is enabled
	if ( ! config.enableNetworkLogging ) {
		debug( 'Network logging disabled, fetch interceptor not initialized' );
		return;
	}

	const originalFetch = window.fetch;

	window.fetch = async function ( input, init ) {
		const startTime = performance.now();
		const requestDetails = extractRequestDetails( input, init );

		let requestBody = null;
		let clonedRequest = null;

		// Try to read request body if present
		try {
			if ( init?.body ) {
				// Body is provided in init options
				if ( typeof init.body === 'string' ) {
					requestBody = init.body;
				} else {
					requestBody = String( init.body );
				}
			} else if ( input instanceof Request ) {
				// Body might be in Request object - clone to read it
				clonedRequest = input.clone();
				requestBody = await serializeBody( clonedRequest );
			}
		} catch ( error ) {
			debug( `Error reading request body: ${ error.message }` );
			requestBody = `[Error reading request body: ${ error.message }]`;
		}

		let response;
		let responseStatus;
		let responseHeaders = {};

		try {
			// Call original fetch
			response = await originalFetch( input, init );

			// Capture response metadata immediately
			const responseClone = response.clone();
			responseStatus = response.status;
			responseHeaders = serializeHeaders( response.headers );
			const duration = Math.round( performance.now() - startTime );

			// Log asynchronously without blocking the response return
			// This prevents Android WebView Response locking issues
			serializeBody( responseClone )
				.then( ( body ) => {
					onNetworkRequest( {
						url: requestDetails.url,
						method: requestDetails.method,
						requestHeaders: serializeHeaders(
							requestDetails.headers
						),
						requestBody,
						status: responseStatus,
						responseHeaders,
						responseBody: body,
						duration,
					} );
				} )
				.catch( ( error ) => {
					// Log without body if reading fails
					onNetworkRequest( {
						url: requestDetails.url,
						method: requestDetails.method,
						requestHeaders: serializeHeaders(
							requestDetails.headers
						),
						requestBody,
						status: responseStatus,
						responseHeaders,
						responseBody: `[Error reading body: ${ error.message }]`,
						duration,
					} );
				} );

			// Return response immediately - don't wait for body serialization
			return response;
		} catch ( error ) {
			// Log failed request
			const duration = Math.round( performance.now() - startTime );

			onNetworkRequest( {
				url: requestDetails.url,
				method: requestDetails.method,
				requestHeaders: serializeHeaders( requestDetails.headers ),
				requestBody,
				status: 0,
				responseHeaders: {},
				responseBody: `[Network error: ${ error.message }]`,
				duration,
			} );

			// Re-throw the error
			throw error;
		}
	};

	window.__fetchInterceptorInitialized = true;
	debug( 'Fetch interceptor initialized' );
}

/**
 * Extracts request details from fetch arguments.
 *
 * @param {string|Request} input The fetch input (URL or Request object).
 * @param {Object}         init  The fetch init options.
 *
 * @return {Object} Request details object.
 */
function extractRequestDetails( input, init = {} ) {
	let url;
	let method = 'GET';
	let headers = {};

	if ( typeof input === 'string' ) {
		url = input;
		method = init.method || 'GET';
		headers = init.headers || {};
	} else if ( input instanceof Request ) {
		url = input.url;
		method = input.method;
		headers = input.headers;
	}

	return {
		url,
		method: method.toUpperCase(),
		headers,
	};
}

/**
 * Reads and serializes request/response body.
 * Handles text, JSON, and binary data.
 *
 * @param {Response|Request} source The Response or Request object.
 *
 * @return {Promise<string|null>} The serialized body or null.
 */
async function serializeBody( source ) {
	try {
		const contentType = source.headers.get( 'content-type' ) || '';

		// Handle JSON
		if ( contentType.includes( 'application/json' ) ) {
			const text = await source.text();
			// Validate it's actually JSON
			try {
				JSON.parse( text );
				return text;
			} catch ( e ) {
				return text;
			}
		}

		// Handle text-based content
		if (
			contentType.includes( 'text/' ) ||
			contentType.includes( 'application/javascript' ) ||
			contentType.includes( 'application/xml' )
		) {
			return await source.text();
		}

		// For binary/blob, just return size info
		if ( source.blob ) {
			const blob = await source.blob();
			return `[Binary data: ${ blob.size } bytes]`;
		}

		// Fallback to text
		return await source.text();
	} catch ( error ) {
		return `[Error reading body: ${ error.message }]`;
	}
}

/**
 * Serializes Headers object to a plain object.
 *
 * @param {Headers} headers The Headers object to serialize.
 *
 * @return {Object} Plain object representation of headers.
 */
function serializeHeaders( headers ) {
	const result = {};
	if ( headers && typeof headers.forEach === 'function' ) {
		headers.forEach( ( value, key ) => {
			result[ key ] = value;
		} );
	}
	return result;
}
