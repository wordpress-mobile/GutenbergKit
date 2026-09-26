/**
 * External dependencies
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

/**
 * WordPress dependencies
 */
import apiFetch from '@wordpress/api-fetch';

/**
 * Internal dependencies
 */
import { configureApiFetch } from './api-fetch';
import * as bridge from './bridge';

vi.mock( './bridge', async ( importOriginal ) => {
	const actual = await importOriginal();
	return {
		...actual,
		getGBKit: vi.fn(),
	};
} );

/**
 * The root is captured when the middleware is created, so it is asserted where
 * it is handed over rather than by issuing a request. That also keeps these
 * cases out of `api-fetch.test.js`, which configures once in `beforeAll` and so
 * cannot vary the root.
 *
 * Each case calls `configureApiFetch()`, and `apiFetch.use()` registers on a
 * module-level array with no way to unregister, so the middlewares accumulate
 * across cases. Do not issue requests from this file; add those to
 * `api-fetch.test.js` instead.
 */
describe( 'configureApiFetch root URL', () => {
	let createRootURLMiddleware;

	beforeEach( () => {
		vi.clearAllMocks();
		createRootURLMiddleware = vi.spyOn(
			apiFetch,
			'createRootURLMiddleware'
		);
	} );

	afterEach( () => {
		createRootURLMiddleware.mockRestore();
	} );

	/**
	 * @param {string} [siteApiRoot] The configured root.
	 * @return {string} The root handed to the root URL middleware.
	 */
	function configuredRoot( siteApiRoot ) {
		bridge.getGBKit.mockReturnValue( { siteApiRoot } );
		configureApiFetch();

		expect( createRootURLMiddleware ).toHaveBeenCalled();
		return createRootURLMiddleware.mock.calls[ 0 ][ 0 ];
	}

	// Both forms are supported input, and the native URL builders normalize
	// both. The root is concatenated with the path, so without the separator
	// the two run together: `https://example.com/wp-jsonwp/v2/posts`.
	it.each( [
		'https://example.com/wp-json',
		'https://example.com/wp-json/',
		'https://example.com/wp-json//',
	] )( 'gives the root %s a single trailing slash', ( siteApiRoot ) => {
		expect( configuredRoot( siteApiRoot ) ).toBe(
			'https://example.com/wp-json/'
		);
	} );

	// A lone slash would instead resolve every request against the page.
	it( 'leaves an unconfigured root empty', () => {
		expect( configuredRoot( undefined ) ).toBe( '' );
	} );
} );
