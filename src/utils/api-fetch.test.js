import {
	describe,
	it,
	expect,
	beforeAll,
	beforeEach,
	afterEach,
	vi,
} from 'vitest';
import apiFetch from '@wordpress/api-fetch';
import { configureApiFetch, withRateLimitRetry } from './api-fetch';
import * as bridge from './bridge';
import * as logger from './logger';

vi.mock( './bridge', async ( importOriginal ) => {
	const actual = await importOriginal();
	return {
		...actual,
		getGBKit: vi.fn(),
	};
} );
vi.mock( './logger' );

describe( 'api-fetch credentials handling', () => {
	let originalFetch;

	beforeAll( () => {
		// Set up initial bridge mock for middleware initialization
		bridge.getGBKit.mockReturnValue( {
			siteApiRoot: 'https://example.com/wp-json/',
		} );

		// Initialize middleware once - it will persist across all tests
		configureApiFetch();
	} );

	beforeEach( () => {
		vi.clearAllMocks();
		originalFetch = global.fetch;
		global.fetch = vi.fn( () =>
			Promise.resolve( {
				ok: true,
				json: () => Promise.resolve( {} ),
			} )
		);
	} );

	afterEach( () => {
		global.fetch = originalFetch;
	} );

	it( 'should set credentials to omit when authHeader is provided', async () => {
		bridge.getGBKit.mockReturnValue( {
			siteApiRoot: 'https://example.com/wp-json/',
			authHeader: 'Bearer test-token',
			siteApiNamespace: [ 'wp/v2' ],
			namespaceExcludedPaths: [],
		} );

		try {
			await apiFetch( { path: '/wp/v2/posts' } );
		} catch {
			// Ignore errors from the actual fetch
		}

		expect( global.fetch ).toHaveBeenCalled();
		const [ , options ] = global.fetch.mock.calls[ 0 ];

		expect( options.credentials ).toBe( 'omit' );
		expect( options.headers.Authorization ).toBe( 'Bearer test-token' );
	} );

	it( 'should not set credentials when authHeader is not provided', async () => {
		bridge.getGBKit.mockReturnValue( {
			siteApiRoot: 'https://example.com/wp-json/',
			authHeader: null,
			siteApiNamespace: [ 'wp/v2' ],
			namespaceExcludedPaths: [],
		} );

		try {
			await apiFetch( { path: '/wp/v2/posts' } );
		} catch {
			// Ignore errors from the actual fetch
		}

		expect( global.fetch ).toHaveBeenCalled();
		const [ , options ] = global.fetch.mock.calls[ 0 ];

		expect( options.credentials ).not.toBe( 'omit' );
		expect( options.headers?.Authorization ).toBeUndefined();
	} );

	it( 'should override existing credentials setting when authHeader is provided', async () => {
		bridge.getGBKit.mockReturnValue( {
			siteApiRoot: 'https://example.com/wp-json/',
			authHeader: 'Bearer override-token',
			siteApiNamespace: [ 'wp/v2' ],
			namespaceExcludedPaths: [],
		} );

		try {
			await apiFetch( {
				path: '/wp/v2/posts',
				credentials: 'include',
			} );
		} catch {
			// Ignore errors from the actual fetch
		}

		expect( global.fetch ).toHaveBeenCalled();
		const [ , options ] = global.fetch.mock.calls[ 0 ];

		expect( options.credentials ).toBe( 'omit' );
		expect( options.headers.Authorization ).toBe( 'Bearer override-token' );
	} );

	describe( 'filterEndpointsMiddleware', () => {
		it( 'filters the post endpoint when restBase and restNamespace are provided', async () => {
			bridge.getGBKit.mockReturnValue( {
				siteApiRoot: 'https://example.com/wp-json/',
				siteApiNamespace: [ 'wp/v2' ],
				namespaceExcludedPaths: [],
				post: {
					id: 42,
					restBase: 'posts',
					restNamespace: 'wp/v2',
				},
			} );

			const result = await apiFetch( { path: '/wp/v2/posts/42' } );

			expect( global.fetch ).not.toHaveBeenCalled();
			expect( result ).toEqual( [] );
		} );

		it( 'falls back to default restBase and restNamespace when omitted from the payload', async () => {
			bridge.getGBKit.mockReturnValue( {
				siteApiRoot: 'https://example.com/wp-json/',
				siteApiNamespace: [ 'wp/v2' ],
				namespaceExcludedPaths: [],
				post: {
					id: 7,
					// restBase and restNamespace intentionally omitted
				},
			} );

			const result = await apiFetch( { path: '/wp/v2/posts/7' } );

			expect( global.fetch ).not.toHaveBeenCalled();
			expect( result ).toEqual( [] );
		} );

		it( 'lets the request through when post id is undefined', async () => {
			bridge.getGBKit.mockReturnValue( {
				siteApiRoot: 'https://example.com/wp-json/',
				siteApiNamespace: [ 'wp/v2' ],
				namespaceExcludedPaths: [],
				post: {},
			} );

			try {
				await apiFetch( { path: '/wp/v2/posts/99' } );
			} catch {
				// Ignore errors from the actual fetch
			}

			expect( global.fetch ).toHaveBeenCalled();
		} );

		it( 'lets the request through when no post payload is present', async () => {
			bridge.getGBKit.mockReturnValue( {
				siteApiRoot: 'https://example.com/wp-json/',
				siteApiNamespace: [ 'wp/v2' ],
				namespaceExcludedPaths: [],
			} );

			try {
				await apiFetch( { path: '/wp/v2/posts/99' } );
			} catch {
				// Ignore errors from the actual fetch
			}

			expect( global.fetch ).toHaveBeenCalled();
		} );
	} );

	describe( 'siteIndexMiddleware', () => {
		const indexPath = '/?_fields=name,home,url,image_sizes';

		it( 'resolves the REST index locally on namespaced sites', async () => {
			bridge.getGBKit.mockReturnValue( {
				siteApiRoot: 'https://public-api.example.com/',
				siteApiNamespace: [ 'sites/123/' ],
				namespaceExcludedPaths: [],
				siteURL: 'https://example.com/',
			} );

			const result = await apiFetch( { path: indexPath } );

			expect( global.fetch ).not.toHaveBeenCalled();
			expect( result ).toEqual( { home: 'https://example.com' } );
		} );

		it( 'resolves an empty record when the site URL is unknown', async () => {
			bridge.getGBKit.mockReturnValue( {
				siteApiRoot: 'https://public-api.example.com/',
				siteApiNamespace: [ 'sites/123/' ],
				namespaceExcludedPaths: [],
			} );

			const result = await apiFetch( { path: '/' } );

			expect( global.fetch ).not.toHaveBeenCalled();
			expect( result ).toEqual( {} );
		} );

		it( 'requests the REST index from sites without a namespace', async () => {
			bridge.getGBKit.mockReturnValue( {
				siteApiRoot: 'https://example.com/wp-json/',
				siteApiNamespace: [],
				namespaceExcludedPaths: [],
				siteURL: 'https://example.com/',
			} );

			await apiFetch( { path: indexPath } );

			expect( global.fetch ).toHaveBeenCalled();
			const [ url ] = global.fetch.mock.calls[ 0 ];
			expect( url ).toMatch(
				/^https:\/\/example\.com\/wp-json\/\?_fields=/
			);
		} );

		it( 'lets non-index requests through on namespaced sites', async () => {
			bridge.getGBKit.mockReturnValue( {
				siteApiRoot: 'https://public-api.example.com/',
				siteApiNamespace: [ 'sites/123/' ],
				namespaceExcludedPaths: [],
				siteURL: 'https://example.com/',
			} );

			try {
				await apiFetch( { path: '/wp/v2/posts' } );
			} catch {
				// Ignore errors from the actual fetch
			}

			expect( global.fetch ).toHaveBeenCalled();
		} );
	} );

	describe( 'apiPathModifierMiddleware', () => {
		/** The URL of the first `fetch` call. */
		function requestedUrl() {
			expect( global.fetch ).toHaveBeenCalled();
			return String( global.fetch.mock.calls[ 0 ][ 0 ] );
		}

		// Both slash forms are supported input and must resolve to the same path;
		// an unslashed namespace otherwise runs into the following segment:
		// `/wp/v2/sites/123posts`. The repeated-slash case pins the quantifier.
		it.each( [ 'sites/123', 'sites/123/', 'sites/123//' ] )(
			'inserts the namespace %s with a single trailing slash',
			async ( namespace ) => {
				bridge.getGBKit.mockReturnValue( {
					siteApiRoot: 'https://example.com/wp-json/',
					siteApiNamespace: [ namespace ],
					namespaceExcludedPaths: [],
				} );

				await apiFetch( { path: '/wp/v2/posts' } ).catch( () => {} );

				expect( requestedUrl() ).toContain( '/wp/v2/sites/123/posts' );
			}
		);
	} );

	describe( 'mediaPermissionsMiddleware', () => {
		beforeEach( () => {
			bridge.getGBKit.mockReturnValue( {
				siteApiRoot: 'https://example.com/wp-json/',
				siteApiNamespace: [ 'wp/v2' ],
				namespaceExcludedPaths: [],
			} );
		} );

		it( 'fills in the Allow header when the browser hides it', async () => {
			global.fetch = vi.fn( () =>
				Promise.resolve( new Response( '{}', { status: 200 } ) )
			);

			const response = await apiFetch( {
				path: '/wp/v2/media',
				method: 'OPTIONS',
				parse: false,
			} );

			expect( response.headers.get( 'allow' ) ).toBe( 'GET, POST' );
		} );

		it( 'keeps the Allow header WordPress sends', async () => {
			global.fetch = vi.fn( () =>
				Promise.resolve(
					new Response( '{}', {
						status: 200,
						headers: { Allow: 'GET' },
					} )
				)
			);

			const response = await apiFetch( {
				path: '/wp/v2/media',
				method: 'OPTIONS',
				parse: false,
			} );

			expect( response.headers.get( 'allow' ) ).toBe( 'GET' );
		} );

		it.each( [
			[ 'a single attachment', '/wp/v2/media/123' ],
			[ 'another collection', '/wp/v2/settings' ],
		] )(
			'leaves the Allow header missing for %s',
			async ( _label, path ) => {
				global.fetch = vi.fn( () =>
					Promise.resolve( new Response( '{}', { status: 200 } ) )
				);

				const response = await apiFetch( {
					path,
					method: 'OPTIONS',
					parse: false,
				} );

				expect( response.headers.get( 'allow' ) ).toBeNull();
			}
		);
	} );

	describe( 'withRateLimitRetry', () => {
		const rateLimited = ( headers = {} ) =>
			Promise.resolve(
				new Response( '<html>Too Many Requests</html>', {
					status: 429,
					headers: { 'Content-Type': 'text/html', ...headers },
				} )
			);
		const okResponse = () =>
			Promise.resolve( new Response( '{"ok":true}', { status: 200 } ) );
		// Responses are compared by status, as their bodies are single-use.
		const settle = ( promise ) =>
			promise.then(
				( value ) => ( { resolved: summarize( value ) } ),
				( err ) => ( { rejected: summarize( err ) } )
			);
		const summarize = ( value ) =>
			value instanceof Response ? { status: value.status } : value;

		beforeEach( () => {
			bridge.getGBKit.mockReturnValue( {
				siteApiRoot: 'https://example.com/wp-json/',
				siteApiNamespace: [],
				namespaceExcludedPaths: [],
			} );
			vi.useFakeTimers();
			vi.spyOn( Math, 'random' ).mockReturnValue( 0 );
		} );

		afterEach( () => {
			vi.useRealTimers();
			vi.restoreAllMocks();
		} );

		it.each( [ 'GET', 'HEAD', 'OPTIONS' ] )(
			'retries a rate-limited %s request',
			async ( method ) => {
				global.fetch = vi
					.fn()
					.mockImplementationOnce( () => rateLimited() )
					.mockImplementationOnce( okResponse );

				const request = apiFetch( {
					path: '/wp/v2/taxonomies',
					method,
					parse: false,
				} );
				await vi.runAllTimersAsync();

				expect( ( await request ).status ).toBe( 200 );
				expect( global.fetch ).toHaveBeenCalledTimes( 2 );
			}
		);

		it( 'resolves with the parsed body of the retried request', async () => {
			global.fetch = vi
				.fn()
				.mockImplementationOnce( () => rateLimited() )
				.mockImplementationOnce( okResponse );

			const request = apiFetch( { path: '/wp/v2/taxonomies' } );
			await vi.runAllTimersAsync();

			expect( await request ).toEqual( { ok: true } );
		} );

		it( 'logs each retry as info rather than a warning', async () => {
			global.fetch = vi
				.fn()
				.mockImplementationOnce( () => rateLimited() )
				.mockImplementationOnce( okResponse );

			const request = apiFetch( { path: '/wp/v2/taxonomies' } );
			await vi.runAllTimersAsync();
			await request;

			expect( logger.info ).toHaveBeenCalledWith(
				expect.stringContaining( 'Retrying GET' )
			);
			expect( logger.warn ).not.toHaveBeenCalled();
		} );

		it( 'waits longer before each retry', async () => {
			global.fetch = vi
				.fn()
				.mockImplementationOnce( () => rateLimited() )
				.mockImplementationOnce( () => rateLimited() )
				.mockImplementationOnce( okResponse );

			const request = apiFetch( { path: '/wp/v2/taxonomies' } );

			await vi.advanceTimersByTimeAsync( 499 );
			expect( global.fetch ).toHaveBeenCalledTimes( 1 );
			await vi.advanceTimersByTimeAsync( 1 );
			expect( global.fetch ).toHaveBeenCalledTimes( 2 );
			await vi.advanceTimersByTimeAsync( 1999 );
			expect( global.fetch ).toHaveBeenCalledTimes( 2 );
			await vi.advanceTimersByTimeAsync( 1 );

			expect( await request ).toEqual( { ok: true } );
			expect( global.fetch ).toHaveBeenCalledTimes( 3 );
		} );

		it( 'adds jitter in proportion to each base delay', async () => {
			vi.spyOn( Math, 'random' ).mockReturnValue( 0.5 );
			global.fetch = vi
				.fn()
				.mockImplementationOnce( () => rateLimited() )
				.mockImplementationOnce( () => rateLimited() )
				.mockImplementationOnce( okResponse );

			const request = apiFetch( { path: '/wp/v2/taxonomies' } );

			await vi.advanceTimersByTimeAsync( 749 );
			expect( global.fetch ).toHaveBeenCalledTimes( 1 );
			await vi.advanceTimersByTimeAsync( 1 );
			expect( global.fetch ).toHaveBeenCalledTimes( 2 );
			await vi.advanceTimersByTimeAsync( 2999 );
			expect( global.fetch ).toHaveBeenCalledTimes( 2 );
			await vi.advanceTimersByTimeAsync( 1 );

			expect( await request ).toEqual( { ok: true } );
			expect( global.fetch ).toHaveBeenCalledTimes( 3 );
		} );

		it( 'waits as long as the Retry-After header asks', async () => {
			global.fetch = vi
				.fn()
				.mockImplementationOnce( () =>
					rateLimited( { 'Retry-After': '3' } )
				)
				.mockImplementationOnce( okResponse );

			const request = apiFetch( { path: '/wp/v2/taxonomies' } );

			await vi.advanceTimersByTimeAsync( 2999 );
			expect( global.fetch ).toHaveBeenCalledTimes( 1 );
			await vi.advanceTimersByTimeAsync( 1 );

			expect( await request ).toEqual( { ok: true } );
		} );

		it( 'waits until the date the Retry-After header names', async () => {
			vi.setSystemTime( new Date( '2026-01-01T00:00:00Z' ) );
			global.fetch = vi
				.fn()
				.mockImplementationOnce( () =>
					rateLimited( {
						'Retry-After': 'Thu, 01 Jan 2026 00:00:03 GMT',
					} )
				)
				.mockImplementationOnce( okResponse );

			const request = apiFetch( { path: '/wp/v2/taxonomies' } );

			await vi.advanceTimersByTimeAsync( 2999 );
			expect( global.fetch ).toHaveBeenCalledTimes( 1 );
			await vi.advanceTimersByTimeAsync( 1 );

			expect( await request ).toEqual( { ok: true } );
		} );

		it( 'waits for a Retry-After delay of up to 10 seconds', async () => {
			global.fetch = vi
				.fn()
				.mockImplementationOnce( () =>
					rateLimited( { 'Retry-After': '10' } )
				)
				.mockImplementationOnce( okResponse );

			const request = apiFetch( { path: '/wp/v2/taxonomies' } );

			await vi.advanceTimersByTimeAsync( 9_999 );
			expect( global.fetch ).toHaveBeenCalledTimes( 1 );
			await vi.advanceTimersByTimeAsync( 1 );

			expect( await request ).toEqual( { ok: true } );
		} );

		it( 'does not retry when Retry-After asks for a longer delay', async () => {
			global.fetch = vi.fn( () =>
				rateLimited( { 'Retry-After': '11' } )
			);

			const request = apiFetch( { path: '/wp/v2/taxonomies' } );
			const assertion = expect( request ).rejects.toMatchObject( {
				code: 'invalid_json',
			} );
			await vi.runAllTimersAsync();

			await assertion;
			expect( global.fetch ).toHaveBeenCalledTimes( 1 );
			expect( logger.warn ).toHaveBeenCalledWith(
				expect.stringContaining( 'Giving up on GET' ),
				{ retries: 0 }
			);
		} );

		it( 'rejects as api-fetch would once retries run out', async () => {
			global.fetch = vi.fn( () => rateLimited() );

			const request = apiFetch( { path: '/wp/v2/taxonomies' } );
			const assertion = expect( request ).rejects.toMatchObject( {
				code: 'invalid_json',
			} );
			await vi.runAllTimersAsync();

			await assertion;
			expect( global.fetch ).toHaveBeenCalledTimes( 3 );
			expect( logger.warn ).toHaveBeenCalledWith(
				expect.stringContaining( 'Giving up on GET' ),
				{ retries: 2 }
			);
		} );

		it( 'rejects with the response once retries run out without parsing', async () => {
			global.fetch = vi.fn( () => rateLimited() );

			const request = apiFetch( {
				path: '/wp/v2/taxonomies',
				parse: false,
			} );
			const assertion = expect( request ).rejects.toMatchObject( {
				status: 429,
			} );
			await vi.runAllTimersAsync();

			await assertion;
		} );

		it( 'does not retry a request that changes server state', async () => {
			global.fetch = vi.fn( () => rateLimited() );

			const request = apiFetch( {
				path: '/wp/v2/posts',
				method: 'POST',
				data: {},
			} );
			const assertion = expect( request ).rejects.toMatchObject( {
				code: 'invalid_json',
			} );
			await vi.runAllTimersAsync();

			await assertion;
			expect( global.fetch ).toHaveBeenCalledTimes( 1 );
		} );

		it( 'does not retry other error responses', async () => {
			global.fetch = vi.fn( () =>
				Promise.resolve(
					new Response( '{"code":"rest_forbidden"}', {
						status: 403,
					} )
				)
			);

			const request = apiFetch( { path: '/wp/v2/taxonomies' } );
			const assertion = expect( request ).rejects.toMatchObject( {
				code: 'rest_forbidden',
			} );
			await vi.runAllTimersAsync();

			await assertion;
			expect( global.fetch ).toHaveBeenCalledTimes( 1 );
		} );

		it( 'does not retry network errors', async () => {
			global.fetch = vi.fn( () =>
				Promise.reject( new TypeError( 'Failed to fetch' ) )
			);

			const request = apiFetch( { path: '/wp/v2/taxonomies' } );
			const assertion = expect( request ).rejects.toMatchObject( {
				code: 'fetch_error',
			} );
			await vi.runAllTimersAsync();

			await assertion;
			expect( global.fetch ).toHaveBeenCalledTimes( 1 );
		} );

		it( 'does not retry an aborted request', async () => {
			const controller = new AbortController();
			global.fetch = vi.fn( () => {
				controller.abort();
				return rateLimited();
			} );

			const request = apiFetch( {
				path: '/wp/v2/taxonomies',
				signal: controller.signal,
			} );
			const assertion = expect( request ).rejects.toMatchObject( {
				code: 'invalid_json',
			} );
			await vi.runAllTimersAsync();

			await assertion;
			expect( global.fetch ).toHaveBeenCalledTimes( 1 );
			expect( logger.warn ).not.toHaveBeenCalled();
		} );

		it.each( [
			[ 'a 204 response', new Response( null, { status: 204 } ), null ],
			[ 'an empty body', new Response( '', { status: 200 } ), null ],
		] )( 'resolves with null for %s', async ( _label, response, body ) => {
			global.fetch = vi.fn( () => Promise.resolve( response ) );

			expect( await apiFetch( { path: '/wp/v2/taxonomies' } ) ).toBe(
				body
			);
		} );

		it( 'rejects invalid JSON in a successful response', async () => {
			global.fetch = vi.fn( () =>
				Promise.resolve( new Response( '<html>', { status: 200 } ) )
			);

			await expect(
				apiFetch( { path: '/wp/v2/taxonomies' } )
			).rejects.toMatchObject( { code: 'invalid_json' } );
		} );

		// The wrapper parses responses itself, so guard against drifting from
		// api-fetch's own parsing when the package updates.
		describe.each( [ true, false ] )( 'with parse: %s', ( parse ) => {
			it.each( [
				[ 'a JSON body', 200, '{"id":1}' ],
				[ 'an empty body', 200, '' ],
				[ 'invalid JSON', 200, '<html>' ],
				[ 'a 204 response', 204, null ],
				[ 'a JSON error', 404, '{"code":"rest_no_route"}' ],
				[ 'an empty error body', 404, '' ],
				[ 'an HTML error', 500, '<html>Error</html>' ],
			] )(
				'settles %s as api-fetch does',
				async ( _label, status, body ) => {
					global.fetch = vi.fn( () =>
						Promise.resolve( new Response( body, { status } ) )
					);
					const options = {
						url: 'https://example.com/wp-json/wp/v2/taxonomies',
						parse,
					};
					const handler = withRateLimitRetry(
						apiFetch.defaultFetchHandler
					);

					expect( await settle( handler( options ) ) ).toEqual(
						await settle( apiFetch.defaultFetchHandler( options ) )
					);
				}
			);
		} );
	} );

	it( 'should preserve other headers when adding Authorization', async () => {
		bridge.getGBKit.mockReturnValue( {
			siteApiRoot: 'https://example.com/wp-json/',
			authHeader: 'Bearer preserve-test',
			siteApiNamespace: [ 'wp/v2' ],
			namespaceExcludedPaths: [],
		} );

		try {
			await apiFetch( {
				path: '/wp/v2/posts',
				headers: {
					'Content-Type': 'application/json',
					'X-Custom-Header': 'custom-value',
				},
			} );
		} catch {
			// Ignore errors from the actual fetch
		}

		expect( global.fetch ).toHaveBeenCalled();
		const [ , options ] = global.fetch.mock.calls[ 0 ];

		expect( options.credentials ).toBe( 'omit' );
		expect( options.headers[ 'Content-Type' ] ).toBe( 'application/json' );
		expect( options.headers[ 'X-Custom-Header' ] ).toBe( 'custom-value' );
		expect( options.headers.Authorization ).toBe( 'Bearer preserve-test' );
	} );
} );
