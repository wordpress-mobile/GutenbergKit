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

	const response = await fetch(
		`${ creds.siteApiRoot }wp-block-editor/v1/settings`,
		{
			headers: { Authorization: creds.authHeader },
		}
	);

	if ( ! response.ok ) {
		throw new Error(
			`Failed to fetch editor settings: ${ response.status } ${ response.statusText }`
		);
	}

	cachedEditorSettings = await response.json();
	return cachedEditorSettings;
}

export const credentials = readCredentials();

/**
 * Get editor settings, fetching from wp-env on first call.
 *
 * @return {Promise<Object>} Editor settings object.
 */
export async function getEditorSettings() {
	return fetchEditorSettings( credentials );
}
