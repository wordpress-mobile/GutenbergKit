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
	const enableNetworkLogging = config.enableNetworkLogging;
	const originalFetch = window.fetch;

	window.fetch = async function ( input, init ) {
		// Gutenberg's httpV1Middleware rewrites PUT/PATCH/DELETE to POST
		// and adds an X-HTTP-Method-Override header.  That header is not
		// in the CORS allow-list for many WordPress hosts (including
		// WordPress.com), so restore the original method before the
		// request hits the network.
		if ( init?.headers?.[ 'X-HTTP-Method-Override' ] ) {
			const { 'X-HTTP-Method-Override': override, ...remainingHeaders } =
				init.headers;
			init = { ...init, method: override, headers: remainingHeaders };
		}

		if ( ! enableNetworkLogging ) {
			return originalFetch.call( this, input, init );
		}

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
					requestBody = serializeRequestBody( init.body );
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
			const responseStatusText =
				response.statusText || getStatusText( response.status );
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
						statusText: responseStatusText,
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
						statusText: responseStatusText,
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
				statusText: '',
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
		// Merge Request headers with init.headers (init takes precedence, like native fetch)
		if ( init.headers ) {
			const requestHeaders = serializeHeaders( input.headers );
			const initHeaders = serializeHeaders( init.headers );
			// Merge with case-insensitive key matching (lowercase all keys)
			const merged = {};
			Object.entries( requestHeaders ).forEach( ( [ key, value ] ) => {
				merged[ key.toLowerCase() ] = value;
			} );
			Object.entries( initHeaders ).forEach( ( [ key, value ] ) => {
				merged[ key.toLowerCase() ] = value;
			} );
			headers = merged;
		} else {
			headers = input.headers;
		}
	}

	return {
		url,
		method: method.toUpperCase(),
		headers,
	};
}

/**
 * Serializes non-string request body objects into readable strings.
 * Handles FormData, Blob, File, ArrayBuffer, and URLSearchParams.
 *
 * @param {*} body The request body to serialize.
 *
 * @return {string} The serialized body representation.
 */
function serializeRequestBody( body ) {
	// FormData - serialize all entries
	if ( body instanceof FormData ) {
		const entries = Array.from( body.entries() );
		const fields = entries
			.map( ( [ key, value ] ) => {
				if ( value instanceof File ) {
					return `${ key }=<File: ${ value.name }, ${
						value.size
					} bytes, type: ${ value.type || 'unknown' }>`;
				}
				if ( value instanceof Blob ) {
					return `${ key }=<Blob: ${ value.size } bytes, type: ${
						value.type || 'unknown'
					}>`;
				}
				// Truncate long string values for readability
				const stringValue = String( value );
				return `${ key }=${
					stringValue.length > 50
						? stringValue.substring( 0, 50 ) + '...'
						: stringValue
				}`;
			} )
			.join( ', ' );
		return `[FormData with ${ entries.length } field(s): ${ fields }]`;
	}

	// File - show file details
	if ( body instanceof File ) {
		return `[File: ${ body.name }, ${ body.size } bytes, type: ${
			body.type || 'unknown'
		}]`;
	}

	// Blob - show size and type
	if ( body instanceof Blob ) {
		return `[Blob: ${ body.size } bytes, type: ${
			body.type || 'unknown'
		}]`;
	}

	// ArrayBuffer - show byte length
	if ( body instanceof ArrayBuffer ) {
		return `[ArrayBuffer: ${ body.byteLength } bytes]`;
	}

	// URLSearchParams - convert to string
	if ( body instanceof URLSearchParams ) {
		return body.toString();
	}

	// ReadableStream - can't read without consuming
	if ( body instanceof ReadableStream ) {
		return '[ReadableStream - cannot serialize without consuming]';
	}

	// Fallback to String conversion
	return String( body );
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
 * Serializes Headers object or plain object to a plain object.
 *
 * @param {Headers|Object} headers The Headers object or plain object to serialize.
 *
 * @return {Object} Plain object representation of headers.
 */
function serializeHeaders( headers ) {
	const result = {};

	// Handle Headers object (has forEach method)
	if ( headers && typeof headers.forEach === 'function' ) {
		headers.forEach( ( value, key ) => {
			result[ key ] = value;
		} );
	}
	// Handle plain object (from init.headers)
	else if ( headers && typeof headers === 'object' ) {
		Object.entries( headers ).forEach( ( [ key, value ] ) => {
			result[ key ] = value;
		} );
	}

	return result;
}

/**
 * Maps HTTP status codes to their standard status text.
 * Used as fallback when response.statusText is empty (common with HTTP/2).
 *
 * @param {number} status The HTTP status code.
 *
 * @return {string} The corresponding status text, or empty string if unknown.
 */
function getStatusText( status ) {
	const statusTexts = {
		// 1xx Informational
		100: 'Continue',
		101: 'Switching Protocols',
		// 2xx Success
		200: 'OK',
		201: 'Created',
		202: 'Accepted',
		203: 'Non-Authoritative Information',
		204: 'No Content',
		205: 'Reset Content',
		206: 'Partial Content',
		// 3xx Redirection
		300: 'Multiple Choices',
		301: 'Moved Permanently',
		302: 'Found',
		303: 'See Other',
		304: 'Not Modified',
		307: 'Temporary Redirect',
		308: 'Permanent Redirect',
		// 4xx Client Error
		400: 'Bad Request',
		401: 'Unauthorized',
		403: 'Forbidden',
		404: 'Not Found',
		405: 'Method Not Allowed',
		406: 'Not Acceptable',
		408: 'Request Timeout',
		409: 'Conflict',
		410: 'Gone',
		413: 'Payload Too Large',
		414: 'URI Too Long',
		415: 'Unsupported Media Type',
		422: 'Unprocessable Entity',
		429: 'Too Many Requests',
		// 5xx Server Error
		500: 'Internal Server Error',
		501: 'Not Implemented',
		502: 'Bad Gateway',
		503: 'Service Unavailable',
		504: 'Gateway Timeout',
	};

	return statusTexts[ status ] || '';
}
