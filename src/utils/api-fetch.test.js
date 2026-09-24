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

	describe( 'withNetworkRetry', () => {
		const networkError = () =>
			Promise.reject( new TypeError( 'Failed to fetch' ) );
		const okResponse = () =>
			Promise.resolve( new Response( '{"ok":true}', { status: 200 } ) );

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
			'retries a %s request that fails at the network level',
			async ( method ) => {
				global.fetch = vi
					.fn()
					.mockImplementationOnce( networkError )
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

		it( 'waits longer before each retry', async () => {
			global.fetch = vi
				.fn()
				.mockImplementationOnce( networkError )
				.mockImplementationOnce( networkError )
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

		it( 'rejects with the network error once retries run out', async () => {
			global.fetch = vi.fn( networkError );

			const request = apiFetch( { path: '/wp/v2/taxonomies' } );
			const assertion = expect( request ).rejects.toMatchObject( {
				code: 'fetch_error',
			} );
			await vi.runAllTimersAsync();

			await assertion;
			expect( global.fetch ).toHaveBeenCalledTimes( 3 );
		} );

		it( 'does not retry a request that changes server state', async () => {
			global.fetch = vi.fn( networkError );

			const request = apiFetch( {
				path: '/wp/v2/posts',
				method: 'POST',
				data: {},
			} );

			await expect( request ).rejects.toMatchObject( {
				code: 'fetch_error',
			} );
			expect( global.fetch ).toHaveBeenCalledTimes( 1 );
		} );

		it( 'does not retry an error response from the server', async () => {
			global.fetch = vi.fn( () =>
				Promise.resolve(
					new Response( '{"code":"rest_forbidden"}', {
						status: 403,
					} )
				)
			);

			await expect(
				apiFetch( { path: '/wp/v2/taxonomies' } )
			).rejects.toMatchObject( { code: 'rest_forbidden' } );
			expect( global.fetch ).toHaveBeenCalledTimes( 1 );
		} );

		it( 'does not retry while the device is offline', async () => {
			vi.spyOn( navigator, 'onLine', 'get' ).mockReturnValue( false );
			global.fetch = vi.fn( networkError );

			await expect(
				apiFetch( { path: '/wp/v2/taxonomies' } )
			).rejects.toMatchObject( { code: 'offline_error' } );
			expect( global.fetch ).toHaveBeenCalledTimes( 1 );
		} );

		it( 'does not retry an aborted request', async () => {
			const controller = new AbortController();
			global.fetch = vi.fn( () => {
				controller.abort();
				return networkError();
			} );

			await expect(
				apiFetch( {
					path: '/wp/v2/taxonomies',
					signal: controller.signal,
				} )
			).rejects.toMatchObject( { code: 'fetch_error' } );
			expect( global.fetch ).toHaveBeenCalledTimes( 1 );
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
