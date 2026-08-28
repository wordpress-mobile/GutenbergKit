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

const SITE_API_ROOT = 'https://example.com/wp-json/';
const RELAY_ROOT = 'gbk-rest:///';

const GBKIT = {
	siteApiRoot: SITE_API_ROOT,
	restRelayRoot: RELAY_ROOT,
	authHeader: 'Bearer test-token',
	siteApiNamespace: [ 'wp/v2' ],
	namespaceExcludedPaths: [],
};

/**
 * A `fetch` response good enough for api-fetch's default handler.
 *
 * @param {Object} response         The response to build.
 * @param {any}    response.body    The parsed JSON body.
 * @param {Object} response.headers The response headers.
 * @param {number} response.status  The HTTP status.
 * @return {Object} The response.
 */
function makeResponse( { body = {}, headers = {}, status = 200 } = {} ) {
	return {
		ok: status >= 200 && status < 300,
		status,
		headers: new Headers( headers ),
		json: () => Promise.resolve( body ),
	};
}

/**
 * The URL and options of the nth `fetch` call.
 *
 * @param {number} index The call index.
 * @return {{url: string, options: Object}} The call's arguments.
 */
function fetchCall( index = 0 ) {
	const [ url, options ] = global.fetch.mock.calls[ index ];
	return { url, options };
}

// The relay middleware and the relay-rooted `createRootURLMiddleware` are
// registered against the api-fetch singleton, so this file keeps its own module
// registry (vitest isolates test files) and configures the chain once.
describe( 'REST relay', () => {
	let originalFetch;

	beforeAll( () => {
		bridge.getGBKit.mockReturnValue( GBKIT );
		configureApiFetch();
	} );

	beforeEach( () => {
		vi.clearAllMocks();
		bridge.getGBKit.mockReturnValue( GBKIT );
		originalFetch = global.fetch;
		global.fetch = vi.fn( () => Promise.resolve( makeResponse() ) );
	} );

	afterEach( () => {
		global.fetch = originalFetch;
	} );

	describe( 'addressing', () => {
		it( 'addresses a request built from a path to the relay', async () => {
			await apiFetch( { path: '/wp/v2/posts' } );

			expect( fetchCall().url ).toMatch(
				/^gbk-rest:\/\/\/wp\/v2\/posts/
			);
		} );

		// `createRootURLMiddleware` only rewrites requests built from a `path`.
		// `fetchAllMiddleware` re-enters with the absolute URL from a `Link`
		// header, and core-data's global styles resolver with one from an
		// `_links` href — both would otherwise bypass the relay.
		it( 'redirects an absolute site API URL back to the relay', async () => {
			await apiFetch( {
				url: `${ SITE_API_ROOT }wp/v2/global-styles/2/revisions`,
			} );

			expect( fetchCall().url ).toMatch(
				/^gbk-rest:\/\/\/wp\/v2\/global-styles\/2\/revisions/
			);
		} );

		// WordPress builds `Link` headers and `_links` hrefs from its own
		// `home_url()`, which need not be the host the app was configured with.
		// Matching on the origin too would leave `per_page=-1` silently failing
		// on every such site.
		it( 'redirects a site API URL that arrives on another host alias', async () => {
			await apiFetch( {
				url: 'http://127.0.0.1:8888/wp-json/wp/v2/tags?page=2',
			} );

			expect( fetchCall().url ).toMatch(
				/^gbk-rest:\/\/\/wp\/v2\/tags\?page=2/
			);
		} );

		it( 'leaves a URL outside the site API root alone', async () => {
			await apiFetch( { url: 'https://other.example.com/thing' } );

			expect( fetchCall().url ).toMatch(
				/^https:\/\/other\.example\.com\/thing/
			);
		} );

		it( 'paginates an unbounded query through the relay', async () => {
			global.fetch = vi
				.fn()
				.mockResolvedValueOnce(
					makeResponse( {
						body: [ { id: 1 } ],
						headers: {
							link: `<${ SITE_API_ROOT }wp/v2/categories?page=2>; rel="next"`,
						},
					} )
				)
				.mockResolvedValueOnce(
					makeResponse( { body: [ { id: 2 } ] } )
				);

			const results = await apiFetch( {
				path: '/wp/v2/categories?per_page=-1',
			} );

			expect( results ).toEqual( [ { id: 1 }, { id: 2 } ] );
			expect( fetchCall( 1 ).url ).toMatch(
				/^gbk-rest:\/\/\/wp\/v2\/categories\?page=2/
			);
		} );
	} );

	// Routing through the normal middleware chain — rather than intercepting
	// the built request and re-issuing it — is what keeps these intact.
	describe( 'request building', () => {
		it( 'sends the body built from options.data', async () => {
			await apiFetch( {
				path: '/wp/v2/posts/1',
				method: 'POST',
				data: { title: 'Hello' },
			} );

			const { options } = fetchCall();
			expect( options.body ).toBe( '{"title":"Hello"}' );
			expect( options.headers[ 'Content-Type' ] ).toBe(
				'application/json'
			);
		} );

		it( 'sends the Accept header WordPress keys REST requests off', async () => {
			await apiFetch( { path: '/wp/v2/posts' } );

			expect( fetchCall().options.headers.Accept ).toBe(
				'application/json, */*;q=0.1'
			);
		} );

		it( 'applies the HTTP v1 method override', async () => {
			await apiFetch( {
				path: '/wp/v2/posts/1',
				method: 'PUT',
				data: { title: 'Hello' },
			} );

			const { options } = fetchCall();
			expect( options.method ).toBe( 'POST' );
			expect( options.headers[ 'X-HTTP-Method-Override' ] ).toBe( 'PUT' );
		} );

		it( 'forwards the abort signal', async () => {
			const controller = new AbortController();

			await apiFetch( {
				path: '/wp/v2/posts',
				signal: controller.signal,
			} );

			expect( fetchCall().options.signal ).toBe( controller.signal );
		} );

		// `canUser` issues `OPTIONS` and reads the `Allow` header, so the relay
		// has to see it as an ordinary request. On this transport nothing is
		// preflighted, so an `OPTIONS` arriving natively is always a real one.
		it( 'sends an OPTIONS request through unchanged', async () => {
			const response = makeResponse( {
				headers: { allow: 'GET, POST' },
			} );
			global.fetch = vi.fn( () => Promise.resolve( response ) );

			const result = await apiFetch( {
				path: '/wp/v2/posts',
				method: 'OPTIONS',
				parse: false,
			} );

			expect( fetchCall().options.method ).toBe( 'OPTIONS' );
			expect( result.headers.get( 'allow' ) ).toBe( 'GET, POST' );
		} );
	} );

	describe( 'request bodies', () => {
		it( 'marks a request that carries a body', async () => {
			await apiFetch( {
				path: '/wp/v2/posts/1',
				method: 'POST',
				data: { title: 'Hello' },
			} );

			expect( fetchCall().options.headers[ 'X-GBK-Relay-Body' ] ).toBe(
				'attached'
			);
		} );

		// `httpV1Middleware` stamps `Content-Type: application/json` on every
		// DELETE whether or not there is a body, so the marker — not the
		// content type — is what tells a withheld body from an absent one.
		it( 'does not mark a bodyless write', async () => {
			await apiFetch( { path: '/wp/v2/posts/1', method: 'DELETE' } );

			const { options } = fetchCall();
			expect( options.headers[ 'X-HTTP-Method-Override' ] ).toBe(
				'DELETE'
			);
			expect( options.headers[ 'X-GBK-Relay-Body' ] ).toBeUndefined();
		} );

		// WebKit hands a scheme handler no bytes for a blob-backed body and no
		// error, so an unguarded request would write nothing and report success.
		it( 'refuses a body the transport cannot carry', async () => {
			const body = new FormData();
			body.append(
				'file',
				new File( [ 'data' ], 'photo.jpg', { type: 'image/jpeg' } )
			);

			await expect(
				apiFetch( { path: '/wp/v2/media', method: 'POST', body } )
			).rejects.toMatchObject( { code: 'relay_body_unavailable' } );
			expect( global.fetch ).not.toHaveBeenCalled();
		} );

		// The boundary is the body's type, not "not a string": a FormData of
		// text fields does reach the handler.
		it( 'allows a FormData carrying only text fields', async () => {
			const body = new FormData();
			body.append( 'title', 'Hello' );

			await apiFetch( { path: '/wp/v2/posts/1', method: 'POST', body } );

			expect( fetchCall().options.headers[ 'X-GBK-Relay-Body' ] ).toBe(
				'attached'
			);
		} );
	} );

	describe( 'when the relay is inactive', () => {
		beforeEach( () => {
			bridge.getGBKit.mockReturnValue( {
				...GBKIT,
				restRelayRoot: undefined,
			} );
		} );

		it( 'leaves an absolute site URL and the body marker alone', async () => {
			await apiFetch( {
				url: `${ SITE_API_ROOT }wp/v2/posts`,
				method: 'POST',
				data: { title: 'Hello' },
			} );

			const { url, options } = fetchCall();
			expect( url ).toBe( `${ SITE_API_ROOT }wp/v2/posts?_locale=user` );
			expect( options.headers[ 'X-GBK-Relay-Body' ] ).toBeUndefined();
		} );
	} );
} );
