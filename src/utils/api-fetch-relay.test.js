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

const API_ROOT = 'https://example.com/wp-json/';
const RELAY_ROOT = 'http://127.0.0.1:5555/proxy/';

const GBKIT = {
	siteApiRoot: API_ROOT,
	siteApiNamespace: [ 'wp/v2' ],
	namespaceExcludedPaths: [],
	authHeader: 'Bearer site-token',
	networkProxy: { port: 5555, token: 'relay-token' },
};

/** The fetch the relay wrapper delegates to; replaced per test. */
let transport;

/**
 * A minimal stand-in for the `Response` the relay returns, carrying only what
 * api-fetch and its middleware read.
 *
 * @param {Object} options         Response shape.
 * @param {number} options.status  HTTP status.
 * @param {any}    options.body    The decoded JSON body, or a rejecting decoder.
 * @param {Object} options.headers Response headers, lowercase-keyed.
 * @return {Object} The response stand-in.
 */
function makeResponse( { status = 200, body = {}, headers = {} } = {} ) {
	return {
		ok: status >= 200 && status < 300,
		status,
		json: () =>
			body instanceof Error
				? Promise.reject( body )
				: Promise.resolve( body ),
		headers: { get: ( name ) => headers[ name.toLowerCase() ] ?? null },
	};
}

/**
 * The arguments the transport received on its nth call.
 *
 * @param {number} index Call index.
 * @return {{url: string, init: Object}} The call.
 */
function transportCall( index = 0 ) {
	const [ url, init ] = transport.mock.calls[ index ];
	return { url, init };
}

/**
 * A header from an intercepted call, case-insensitively.
 *
 * @param {Object} init The `fetch` init the transport received.
 * @param {string} name The header name.
 * @return {string|null} The header value.
 */
function header( init, name ) {
	return new Headers( init.headers ).get( name );
}

describe( 'REST relay transport', () => {
	beforeAll( () => {
		// The relay's connection details are read from the injected global
		// rather than through `getGBKit`, so they have to be there.
		window.GBKit = GBKIT;
		bridge.getGBKit.mockReturnValue( GBKIT );

		// A stable indirection so each test can swap the fetch the relay
		// delegates to; the chain captures whatever `window.fetch` is at
		// install time.
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

	describe( 'request', () => {
		it( 'sends the upstream path below the API root to the relay route', async () => {
			await apiFetch( { path: '/wp/v2/posts' } );

			expect( transportCall().url ).toBe(
				`${ RELAY_ROOT }wp/v2/posts?_locale=user`
			);
		} );

		it( 'authenticates to the relay without sending the site credential', async () => {
			await apiFetch( { path: '/wp/v2/posts' } );

			const { init } = transportCall();
			expect( header( init, 'Relay-Authorization' ) ).toBe(
				'Bearer relay-token'
			);
			// The relay injects the site credential natively, so it must not
			// travel over loopback.
			expect( header( init, 'Authorization' ) ).toBeNull();
		} );

		it( 'sends the Accept header WordPress uses to recognize a REST request', async () => {
			await apiFetch( { path: '/wp/v2/posts' } );

			expect( header( transportCall().init, 'Accept' ) ).toBe(
				'application/json, */*;q=0.1'
			);
		} );

		it( 'serializes `data` into a JSON body', async () => {
			await apiFetch( {
				path: '/wp/v2/posts/1',
				method: 'POST',
				data: { title: 'Hello' },
			} );

			const { init } = transportCall();
			expect( init.body ).toBe( JSON.stringify( { title: 'Hello' } ) );
			expect( header( init, 'Content-Type' ) ).toBe( 'application/json' );
		} );

		it( 'applies the HTTP v1 method override', async () => {
			await apiFetch( {
				path: '/wp/v2/posts/1',
				method: 'PUT',
				data: { title: 'Hello' },
			} );

			const { init } = transportCall();
			expect( init.method ).toBe( 'POST' );
			expect( header( init, 'X-HTTP-Method-Override' ) ).toBe( 'PUT' );
		} );

		it( 'forwards an abort signal', async () => {
			const controller = new AbortController();
			await apiFetch( {
				path: '/wp/v2/posts',
				signal: controller.signal,
			} );

			expect( transportCall().init.signal ).toBe( controller.signal );
		} );

		it( 'does not send credentials the relay would reject', async () => {
			// The relay answers `Access-Control-Allow-Origin: *`, which a
			// browser refuses to pair with a credentialed request — and
			// api-fetch defaults `credentials` to `include`.
			await apiFetch( { path: '/wp/v2/posts' } );

			expect( transportCall().init.credentials ).toBe( 'omit' );
		} );

		it( 'relays the absolute URL of a paginated next page', async () => {
			// `fetchAllMiddleware` follows the absolute URL WordPress puts in
			// the `Link` header, so the transport has to recognize the site's
			// own API root in it.
			transport = vi
				.fn()
				.mockResolvedValueOnce(
					makeResponse( {
						body: [ { id: 1 } ],
						headers: {
							link: `<${ API_ROOT }wp/v2/posts?page=2>; rel="next"`,
						},
					} )
				)
				.mockResolvedValueOnce(
					makeResponse( { body: [ { id: 2 } ] } )
				);

			const result = await apiFetch( {
				path: '/wp/v2/posts?per_page=-1',
			} );

			// `per_page=-1` is expanded by api-fetch's own middleware rather
			// than forwarded verbatim, which WordPress would reject.
			expect( transportCall( 0 ).url ).toContain( 'per_page=100' );
			expect( transportCall( 0 ).url ).not.toContain( 'per_page=-1' );
			expect( transportCall( 1 ).url ).toBe(
				`${ RELAY_ROOT }wp/v2/posts?page=2&_locale=user`
			);
			expect( result ).toEqual( [ { id: 1 }, { id: 2 } ] );
		} );

		it( 'relays a next page that arrives on a host alias', async () => {
			// WordPress builds `Link` from `home_url()`, which need not be the
			// host the app was configured with — `www.` versus bare, a mapped
			// domain, `http` behind `https`. wp-env is the everyday case: its
			// credentials report `localhost` while WordPress reports
			// `127.0.0.1`.
			transport = vi
				.fn()
				.mockResolvedValueOnce(
					makeResponse( {
						body: [ { id: 1 } ],
						headers: {
							link: '<https://www.example.com/wp-json/wp/v2/posts?page=2>; rel="next"',
						},
					} )
				)
				.mockResolvedValueOnce(
					makeResponse( { body: [ { id: 2 } ] } )
				);

			const result = await apiFetch( {
				path: '/wp/v2/posts?per_page=-1',
			} );

			expect( transportCall( 1 ).url ).toBe(
				`${ RELAY_ROOT }wp/v2/posts?page=2&_locale=user`
			);
			expect( result ).toEqual( [ { id: 1 }, { id: 2 } ] );
		} );

		it( 'preserves a percent-encoded value in a relayed next page', async () => {
			// Matching moves the target onto the API root's origin, which
			// re-parses it. An encoded value has to survive that unchanged.
			transport = vi
				.fn()
				.mockResolvedValueOnce(
					makeResponse( {
						body: [ { id: 1 } ],
						headers: {
							link: `<${ API_ROOT }wp/v2/posts?search=caf%C3%A9&page=2>; rel="next"`,
						},
					} )
				)
				.mockResolvedValueOnce(
					makeResponse( { body: [ { id: 2 } ] } )
				);

			await apiFetch( { path: '/wp/v2/posts?per_page=-1' } );

			expect( transportCall( 1 ).url ).toContain( 'search=caf%C3%A9' );
		} );

		it( 'leaves a request for somewhere other than the site API alone', async () => {
			await apiFetch( { url: 'https://elsewhere.example/x' } );

			const { url, init } = transportCall();
			expect( url ).toBe( 'https://elsewhere.example/x?_locale=user' );
			expect( header( init, 'Relay-Authorization' ) ).toBeNull();
		} );
	} );

	describe( 'response', () => {
		it( 'resolves the decoded body', async () => {
			transport = vi.fn( () =>
				Promise.resolve( makeResponse( { body: { id: 7 } } ) )
			);

			await expect(
				apiFetch( { path: '/wp/v2/posts/7' } )
			).resolves.toEqual( { id: 7 } );
		} );

		it( 'resolves a 204 to null', async () => {
			transport = vi.fn( () =>
				Promise.resolve( makeResponse( { status: 204 } ) )
			);

			await expect(
				apiFetch( { path: '/wp/v2/posts/7' } )
			).resolves.toBeNull();
		} );

		it( 'returns the raw response when parsing is declined', async () => {
			const response = makeResponse( {
				headers: { allow: 'GET, POST' },
			} );
			transport = vi.fn( () => Promise.resolve( response ) );

			// `canUser` reads the `Allow` header off an unparsed response.
			const result = await apiFetch( {
				path: '/wp/v2/posts',
				method: 'OPTIONS',
				parse: false,
			} );

			expect( result ).toBe( response );
			expect( result.headers.get( 'allow' ) ).toBe( 'GET, POST' );
		} );

		it( 'throws the decoded error body of a failed request', async () => {
			transport = vi.fn( () =>
				Promise.resolve(
					makeResponse( {
						status: 403,
						body: {
							code: 'rest_cannot_edit',
							message: 'Sorry, you are not allowed to do that.',
						},
					} )
				)
			);

			await expect(
				apiFetch( { path: '/wp/v2/posts/7' } )
			).rejects.toMatchObject( { code: 'rest_cannot_edit' } );
		} );

		it( 'normalizes an undecodable body', async () => {
			transport = vi.fn( () =>
				Promise.resolve(
					makeResponse( { body: new Error( 'not json' ) } )
				)
			);

			await expect(
				apiFetch( { path: '/wp/v2/posts/7' } )
			).rejects.toMatchObject( { code: 'invalid_json' } );
		} );

		it( 'normalizes a transport failure', async () => {
			transport = vi.fn( () =>
				Promise.reject( new TypeError( 'Load failed' ) )
			);

			await expect(
				apiFetch( { path: '/wp/v2/posts/7' } )
			).rejects.toMatchObject( { code: 'fetch_error' } );
		} );
	} );
} );
