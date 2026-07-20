const MAX_FETCH_ATTEMPTS = 15;
const FETCH_RETRY_DELAY_MS = 2000;

const delay = ( ms ) => new Promise( ( resolve ) => setTimeout( resolve, ms ) );

/** Marks a failure that retrying cannot resolve, so the loop gives up at once. */
class NonRetryableError extends Error {}

/**
 * Fetch and parse JSON from a wp-env REST endpoint, retrying on transient
 * failures.
 *
 * During warm-up the Playground/wp-env instance can briefly return a 5xx or
 * leak a PHP notice into the body, which corrupts the JSON. Both surface here
 * as errors we retry, and the last failure carries a snippet of the body so a
 * genuine leak is diagnosable instead of an opaque "Unexpected token '<'".
 *
 * A 4xx other than 408/429 means the request itself is wrong — bad credentials
 * or a wrong route — so it fails immediately rather than after the full retry
 * budget.
 *
 * @param {string} url   Fully-qualified REST URL.
 * @param {Object} creds Credentials object from readCredentials().
 * @param {string} label Human-readable resource name for error messages.
 * @return {Promise<Object>} The parsed JSON response.
 */
export async function fetchJson( url, creds, label ) {
	let lastError;

	for ( let attempt = 1; attempt <= MAX_FETCH_ATTEMPTS; attempt++ ) {
		try {
			const response = await fetch( url, {
				headers: { Authorization: creds.authHeader },
			} );

			const body = await response.text();

			if ( ! response.ok ) {
				const message = `HTTP ${ response.status } ${
					response.statusText
				} — ${ body.slice( 0, 200 ) }`;

				if (
					response.status < 500 &&
					response.status !== 408 &&
					response.status !== 429
				) {
					throw new NonRetryableError(
						`Failed to fetch ${ label }: ${ message }`
					);
				}

				throw new Error( message );
			}

			try {
				return JSON.parse( body );
			} catch {
				throw new Error(
					`response was not valid JSON — ${ body.slice( 0, 200 ) }`
				);
			}
		} catch ( error ) {
			if ( error instanceof NonRetryableError ) {
				throw error;
			}
			lastError = error;
			if ( attempt < MAX_FETCH_ATTEMPTS ) {
				await delay( FETCH_RETRY_DELAY_MS );
			}
		}
	}

	throw new Error(
		`Failed to fetch ${ label } after ${ MAX_FETCH_ATTEMPTS } attempts: ${ lastError.message }`
	);
}
