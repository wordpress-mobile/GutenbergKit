/**
 * External dependencies
 */
import fs from 'node:fs';
import path from 'node:path';

const CREDENTIALS_PATH = path.resolve(
	import.meta.dirname,
	'../.wp-env.credentials.json'
);

/**
 * Read wp-env credentials from the JSON file written by bin/wp-env-setup.sh.
 *
 * @return {Object} Credentials object with siteUrl, siteApiRoot, authHeader, etc.
 */
function readCredentials() {
	if ( ! fs.existsSync( CREDENTIALS_PATH ) ) {
		throw new Error(
			`wp-env credentials not found at ${ CREDENTIALS_PATH }.\n` +
				'Run "make wp-env-start" to provision the local WordPress environment.'
		);
	}
	return JSON.parse( fs.readFileSync( CREDENTIALS_PATH, 'utf-8' ) );
}

/** Cached editor settings — fetched once and reused across all tests. */
let cachedEditorSettings = null;

/** Cached editor assets — fetched once and reused across all tests. */
let cachedEditorAssets = null;

const MAX_FETCH_ATTEMPTS = 5;
const FETCH_RETRY_DELAY_MS = 1000;

const delay = ( ms ) => new Promise( ( resolve ) => setTimeout( resolve, ms ) );

/**
 * Fetch and parse JSON from a wp-env REST endpoint, retrying on transient
 * failures.
 *
 * During warm-up the Playground/wp-env instance can briefly return a 5xx or
 * leak a PHP notice into the body, which corrupts the JSON. Both surface here
 * as errors we retry, and the last failure carries a snippet of the body so a
 * genuine leak is diagnosable instead of an opaque "Unexpected token '<'".
 *
 * @param {string} url   Fully-qualified REST URL.
 * @param {Object} creds Credentials object from readCredentials().
 * @param {string} label Human-readable resource name for error messages.
 * @return {Promise<Object>} The parsed JSON response.
 */
async function fetchJson( url, creds, label ) {
	let lastError;

	for ( let attempt = 1; attempt <= MAX_FETCH_ATTEMPTS; attempt++ ) {
		try {
			const response = await fetch( url, {
				headers: { Authorization: creds.authHeader },
			} );

			const body = await response.text();

			if ( ! response.ok ) {
				throw new Error(
					`HTTP ${ response.status } ${
						response.statusText
					} — ${ body.slice( 0, 200 ) }`
				);
			}

			try {
				return JSON.parse( body );
			} catch {
				throw new Error(
					`response was not valid JSON — ${ body.slice( 0, 200 ) }`
				);
			}
		} catch ( error ) {
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

/**
 * Fetch editor settings from the wp-env WordPress instance.
 *
 * The result is cached in module scope so the REST call is made only once
 * per test run.
 *
 * @param {Object} creds Credentials object from readCredentials().
 * @return {Promise<Object>} Editor settings suitable for window.GBKit.editorSettings.
 */
async function fetchEditorSettings( creds ) {
	if ( cachedEditorSettings ) {
		return cachedEditorSettings;
	}

	cachedEditorSettings = await fetchJson(
		`${ creds.siteApiRoot }wp-block-editor/v1/settings`,
		creds,
		'editor settings'
	);
	return cachedEditorSettings;
}

/**
 * Fetch editor assets (plugin/theme scripts and styles) from wp-env.
 *
 * @param {Object} creds Credentials object from readCredentials().
 * @return {Promise<Object>} Editor assets suitable for window.GBKit.editorAssets.
 */
async function fetchEditorAssets( creds ) {
	if ( cachedEditorAssets ) {
		return cachedEditorAssets;
	}

	const url = new URL( `${ creds.siteApiRoot }wpcom/v2/editor-assets` );
	url.searchParams.set( 'exclude', 'core,gutenberg' );

	cachedEditorAssets = await fetchJson(
		url.toString(),
		creds,
		'editor assets'
	);
	return cachedEditorAssets;
}

export const credentials = readCredentials();

/**
 * Hostname-agnostic pattern for matching wp-env upload URLs.
 *
 * The Playground runtime may resolve localhost to 127.0.0.1 in WordPress's
 * WP_SITEURL, so we can't assert a specific hostname. Instead we derive
 * the port from the credentials and match against the uploads path.
 *
 * @type {string}
 */
const port = new URL( credentials.siteUrl ).port;
export const uploadsPathPattern = `:${ port }/wp-content/uploads/`;

/**
 * Get editor settings, fetching from wp-env on first call.
 *
 * @return {Promise<Object>} Editor settings object.
 */
export async function getEditorSettings() {
	return fetchEditorSettings( credentials );
}

/**
 * Get editor assets, fetching from wp-env on first call.
 *
 * @return {Promise<Object>} Editor assets object.
 */
export async function getEditorAssets() {
	return fetchEditorAssets( credentials );
}
