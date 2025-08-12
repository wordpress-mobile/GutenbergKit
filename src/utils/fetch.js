/**
 * Basic fetch implementation based on `@wordpress/api-fetch`.
 *
 * @param {string} url     The URL to fetch.
 * @param {Object} options Fetch options.
 * @return {Promise<any>} Fetch promise.
 */
export function basicFetch( url, options = {} ) {
	const responsePromise = window.fetch( url, options );

	return responsePromise.then(
		( value ) =>
			Promise.resolve( value )
				.then( checkStatus )
				.catch( ( response ) => parseAndThrowError( response ) )
				.then( ( response ) =>
					parseResponseAndNormalizeError( response )
				),
		( err ) => {
			// Re-throw AbortError for the users to handle it themselves.
			if ( err && err.name === 'AbortError' ) {
				throw err;
			}

			// Otherwise, there is most likely no network connection.
			// Unfortunately the message might depend on the browser.
			throw {
				code: 'fetch_error',
				message: 'You are probably offline.',
			};
		}
	);
}

/**
 * Checks the status of a response, throwing an error if the status is not in the 200 range.
 *
 * @param {Response} response
 * @return {Response} The response if the status is in the 200 range.
 */
function checkStatus( response ) {
	if ( response.status >= 200 && response.status < 300 ) {
		return response;
	}

	throw response;
}

/**
 * Parses a response, throwing an error if parsing the response fails.
 *
 * @param {Response} response
 * @return {Promise<any>} Parsed response.
 */
function parseAndThrowError( response ) {
	return parseJsonAndNormalizeError( response ).then( ( error ) => {
		const unknownError = {
			code: 'unknown_error',
			message: 'An unknown error occurred.',
		};

		throw error || unknownError;
	} );
}

/**
 * Calls the `json` function on the Response, throwing an error if the response
 * doesn't have a json function or if parsing the json itself fails.
 *
 * @param {Response} response
 * @return {Promise<any>} Parsed response.
 */
const parseJsonAndNormalizeError = ( response ) => {
	const invalidJsonError = {
		code: 'invalid_json',
		message: 'The response is not a valid JSON response.',
	};

	if ( ! response || ! response.json ) {
		throw invalidJsonError;
	}

	return response.json().catch( () => {
		throw invalidJsonError;
	} );
};

/**
 * Parses the fetch response properly and normalize response errors.
 *
 * @param {Response} response
 *
 * @return {Promise<any>} Parsed response.
 */
function parseResponseAndNormalizeError( response ) {
	return Promise.resolve( parseResponse( response ) ).catch( ( res ) =>
		parseAndThrowError( res )
	);
}

/**
 * Parses the fetch response.
 *
 * @param {Response} response
 *
 * @return {Promise<any> | null | Response} Parsed response.
 */
function parseResponse( response ) {
	if ( response.status === 204 ) {
		return null;
	}

	return response.json ? response.json() : Promise.reject( response );
}
