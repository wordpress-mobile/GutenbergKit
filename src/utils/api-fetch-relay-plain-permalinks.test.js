/**
 * External dependencies
 */
import {
	describe,
	it,
	expect,
	beforeAll,
	beforeEach,
	afterEach,
	vi,
} from 'vitest';

/**
 * WordPress dependencies
 */
import apiFetch from '@wordpress/api-fetch';

/**
 * Internal dependencies
 */
import { configureApiFetch } from './api-fetch';
import { installFetchWrappers } from './fetch-chain';
import { createRelayFetchWrapper } from './fetch-relay';
import * as bridge from './bridge';

vi.mock( './bridge', async ( importOriginal ) => {
	const actual = await importOriginal();
	return {
		...actual,
		getGBKit: vi.fn(),
	};
} );

vi.mock( './logger', () => ( {
	debug: vi.fn(),
	info: vi.fn(),
	warn: vi.fn(),
	error: vi.fn(),
} ) );

/** The root WordPress advertises for a site on plain permalinks. */
const API_ROOT = 'https://example.com/index.php?rest_route=%2F';
const RELAY_ROOT = 'http://127.0.0.1:5555/proxy/';

const GBKIT = {
	siteApiRoot: API_ROOT,
	siteApiNamespace: [ 'wp/v2' ],
	namespaceExcludedPaths: [],
	authHeader: 'Bearer site-token',
	networkProxy: {
		port: 5555,
		token: 'relay-token',
		baseURL: RELAY_ROOT,
	},
};

/** The fetch the relay wrapper delegates to; replaced per test. */
let transport;

/**
 * A minimal stand-in for the `Response` the relay returns, carrying only what
 * api-fetch and its middleware read.
 *
 * @param {Object} options         Response shape.
 * @param {number} options.status  HTTP status.
 * @param {any}    options.body    The decoded JSON body.
 * @param {Object} options.headers Response headers, lowercase-keyed.
 * @return {Object} The response stand-in.
 */
function makeResponse( { status = 200, body = {}, headers = {} } = {} ) {
	return {
		ok: status >= 200 && status < 300,
		status,
		json: () => Promise.resolve( body ),
		headers: { get: ( name ) => headers[ name.toLowerCase() ] ?? null },
	};
}

/**
 * The URL the transport received on its nth call.
 *
 * @param {number} index Call index.
 * @return {string} The URL.
 */
function transportURL( index = 0 ) {
	return transport.mock.calls[ index ][ 0 ];
}

// The pretty-permalink counterpart lives in `api-fetch-relay.test.js`. A
// plain-permalink root is a separate file because the fetch chain installs
// once per page, and the relay reads its root at install time.
describe( 'REST relay transport on plain permalinks', () => {
	beforeAll( () => {
		window.GBKit = GBKIT;
		bridge.getGBKit.mockReturnValue( GBKIT );

		window.fetch = ( ...args ) => transport( ...args );
		installFetchWrappers( [ createRelayFetchWrapper() ] );

		configureApiFetch();
	} );

	beforeEach( () => {
		bridge.getGBKit.mockReturnValue( GBKIT );
		transport = vi.fn( () => Promise.resolve( makeResponse() ) );
	} );

	afterEach( () => {
		vi.clearAllMocks();
	} );

	it( 'relays a request whose route api-fetch re-encoded', async () => {
		// The locale middleware runs after the root URL middleware and
		// rebuilds the query, so the route arrives as `%2Fwp%2Fv2%2Fposts`.
		await apiFetch( { path: '/wp/v2/posts' } );

		expect( transportURL() ).toBe(
			`${ RELAY_ROOT }wp/v2/posts?_locale=user`
		);
	} );

	it( 'carries the query of a relayed request', async () => {
		await apiFetch( { path: '/wp/v2/posts?context=edit&per_page=10' } );

		expect( transportURL() ).toBe(
			`${ RELAY_ROOT }wp/v2/posts?context=edit&per_page=10&_locale=user`
		);
	} );

	it( 'relays the next page WordPress names in Link', async () => {
		// WordPress builds the URL through `add_query_arg`, which encodes
		// the route the same way.
		transport = vi
			.fn()
			.mockResolvedValueOnce(
				makeResponse( {
					body: [ { id: 1 } ],
					headers: {
						link: '<https://example.com/index.php?rest_route=%2Fwp%2Fv2%2Fposts&page=2>; rel="next"',
					},
				} )
			)
			.mockResolvedValueOnce( makeResponse( { body: [ { id: 2 } ] } ) );

		const result = await apiFetch( { path: '/wp/v2/posts?per_page=-1' } );

		expect( transportURL( 1 ) ).toBe(
			`${ RELAY_ROOT }wp/v2/posts?page=2&_locale=user`
		);
		expect( result ).toEqual( [ { id: 1 }, { id: 2 } ] );
	} );
} );
