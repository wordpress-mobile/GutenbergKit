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
 * The arguments of the nth `fetch` call, as `{ url, init }`.
 *
 * @param {number} index Call index.
 * @return {{url: string, init: Object}} The call.
 */
function fetchCall( index = 0 ) {
	const [ url, init ] = global.fetch.mock.calls[ index ];
	return { url, init };
}

describe( 'REST relay transport', () => {
	beforeAll( () => {
		// The relay's connection details are read from the injected global
		// rather than through `getGBKit`, so they have to be there.
		window.GBKit = GBKIT;
		bridge.getGBKit.mockReturnValue( GBKIT );
		configureApiFetch();
	} );

	beforeEach( () => {
		bridge.getGBKit.mockReturnValue( GBKIT );
		global.fetch = vi.fn( () => Promise.resolve( makeResponse() ) );
	} );

	afterEach( () => {
		vi.clearAllMocks();
	} );

	describe( 'request', () => {
		it( 'sends the upstream path below the API root to the relay route', async () => {
			await apiFetch( { path: '/wp/v2/posts' } );

			const { url } = fetchCall();
			expect( url ).toBe( `${ RELAY_ROOT }wp/v2/posts?_locale=user` );
		} );

		it( 'authenticates to the relay without sending the site credential', async () => {
			await apiFetch( { path: '/wp/v2/posts' } );

			const { init } = fetchCall();
			expect( init.headers[ 'Relay-Authorization' ] ).toBe(
				'Bearer relay-token'
			);
			// The relay injects the site credential natively, so it must not
			// travel over loopback.
			expect( init.headers.Authorization ).toBeUndefined();
		} );

		it( 'sends the Accept header WordPress uses to recognize a REST request', async () => {
			await apiFetch( { path: '/wp/v2/posts' } );

			expect( fetchCall().init.headers.Accept ).toBe(
				'application/json, */*;q=0.1'
			);
		} );

		it( 'serializes `data` into a JSON body', async () => {
			await apiFetch( {
				path: '/wp/v2/posts/1',
				method: 'POST',
				data: { title: 'Hello' },
			} );

			const { init } = fetchCall();
			expect( init.body ).toBe( JSON.stringify( { title: 'Hello' } ) );
			expect( init.headers[ 'Content-Type' ] ).toBe( 'application/json' );
		} );

		it( 'applies the HTTP v1 method override', async () => {
			await apiFetch( {
				path: '/wp/v2/posts/1',
				method: 'PUT',
				data: { title: 'Hello' },
			} );

			const { init } = fetchCall();
			expect( init.method ).toBe( 'POST' );
			expect( init.headers[ 'X-HTTP-Method-Override' ] ).toBe( 'PUT' );
		} );

		it( 'forwards an abort signal', async () => {
			const controller = new AbortController();
			await apiFetch( {
				path: '/wp/v2/posts',
				signal: controller.signal,
			} );

			expect( fetchCall().init.signal ).toBe( controller.signal );
		} );

		it( 'does not send credentials the relay would reject', async () => {
			// The relay answers `Access-Control-Allow-Origin: *`, which a
			// browser refuses to pair with a credentialed request — and
			// api-fetch defaults `credentials` to `include`.
			await apiFetch( { path: '/wp/v2/posts' } );

			expect( fetchCall().init.credentials ).toBeUndefined();
		} );

		it( 'relays the absolute URL of a paginated next page', async () => {
			// `fetchAllMiddleware` follows the absolute URL WordPress puts in
			// the `Link` header, so the transport has to recognize the site's
			// own API root in it.
			global.fetch = vi
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
			expect( fetchCall( 0 ).url ).toContain( 'per_page=100' );
			expect( fetchCall( 0 ).url ).not.toContain( 'per_page=-1' );
			expect( fetchCall( 1 ).url ).toBe(
				`${ RELAY_ROOT }wp/v2/posts?page=2&_locale=user`
			);
			expect( result ).toEqual( [ { id: 1 }, { id: 2 } ] );
		} );

		it( 'refuses a request for somewhere other than the site API', async () => {
			await expect(
				apiFetch( { url: 'https://elsewhere.example/x' } )
			).rejects.toMatchObject( { code: 'fetch_error' } );

			expect( global.fetch ).not.toHaveBeenCalled();
		} );
	} );

	describe( 'response', () => {
		it( 'resolves the decoded body', async () => {
			global.fetch = vi.fn( () =>
				Promise.resolve( makeResponse( { body: { id: 7 } } ) )
			);

			await expect(
				apiFetch( { path: '/wp/v2/posts/7' } )
			).resolves.toEqual( { id: 7 } );
		} );

		it( 'resolves a 204 to null', async () => {
			global.fetch = vi.fn( () =>
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
			global.fetch = vi.fn( () => Promise.resolve( response ) );

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
			global.fetch = vi.fn( () =>
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
			global.fetch = vi.fn( () =>
				Promise.resolve(
					makeResponse( { body: new Error( 'not json' ) } )
				)
			);

			await expect(
				apiFetch( { path: '/wp/v2/posts/7' } )
			).rejects.toMatchObject( { code: 'invalid_json' } );
		} );

		it( 'normalizes a transport failure', async () => {
			global.fetch = vi.fn( () =>
				Promise.reject( new TypeError( 'Load failed' ) )
			);

			await expect(
				apiFetch( { path: '/wp/v2/posts/7' } )
			).rejects.toMatchObject( { code: 'fetch_error' } );
		} );

		it( 're-throws an abort for the caller to handle', async () => {
			const abortError = new DOMException( 'Aborted', 'AbortError' );
			global.fetch = vi.fn( () => Promise.reject( abortError ) );

			await expect( apiFetch( { path: '/wp/v2/posts/7' } ) ).rejects.toBe(
				abortError
			);
		} );
	} );
} );
