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
import {
	configureApiFetch,
	postTypesFallbackMiddleware,
	withEditedPostType,
	withRateLimitRetry,
} from './api-fetch';
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

	describe( 'blockPostWritesMiddleware', () => {
		const gbkit = {
			siteApiRoot: 'https://example.com/wp-json/',
			siteApiNamespace: [ 'wp/v2' ],
			namespaceExcludedPaths: [],
			post: {
				id: 42,
				restBase: 'posts',
				restNamespace: 'wp/v2',
			},
		};

		it.each( [
			[ 'PUT', '/wp/v2/posts/42' ],
			[ 'post', '/wp/v2/posts/42?_locale=user' ],
			[ 'DELETE', '/wp/v2/posts/42' ],
			[ 'POST', '/wp/v2/posts/42/autosaves' ],
		] )( 'rejects %s %s', async ( method, path ) => {
			bridge.getGBKit.mockReturnValue( gbkit );

			await expect( apiFetch( { path, method } ) ).rejects.toMatchObject(
				{ code: 'gutenberg_kit_post_write_blocked' }
			);
			expect( global.fetch ).not.toHaveBeenCalled();
			expect( logger.warn ).toHaveBeenCalled();
		} );

		it.each( [
			[ 'GET', '/wp/v2/posts/42' ],
			[ 'OPTIONS', '/wp/v2/posts/42' ],
			[ 'PUT', '/wp/v2/posts/421' ],
			[ 'POST', '/wp/v2/posts' ],
			[ 'POST', '/wp/v2/pages/42' ],
		] )( 'lets %s %s through', async ( method, path ) => {
			bridge.getGBKit.mockReturnValue( gbkit );

			await apiFetch( { path, method } );

			expect( global.fetch ).toHaveBeenCalled();
		} );

		it( 'falls back to default restBase and restNamespace when omitted from the payload', async () => {
			bridge.getGBKit.mockReturnValue( {
				...gbkit,
				post: {
					id: 7,
					// restBase and restNamespace intentionally omitted
				},
			} );

			await expect(
				apiFetch( { path: '/wp/v2/posts/7', method: 'PUT' } )
			).rejects.toMatchObject( {
				code: 'gutenberg_kit_post_write_blocked',
			} );
			expect( global.fetch ).not.toHaveBeenCalled();
		} );

		it( 'lets writes through when no post payload is present', async () => {
			bridge.getGBKit.mockReturnValue( {
				siteApiRoot: 'https://example.com/wp-json/',
				siteApiNamespace: [ 'wp/v2' ],
				namespaceExcludedPaths: [],
			} );

			await apiFetch( { path: '/wp/v2/posts/99', method: 'PUT' } );

			expect( global.fetch ).toHaveBeenCalled();
		} );
	} );

	describe( 'withEditedPostType', () => {
		const typesPath = '/wp/v2/types?context=view';
		const preloadData = {
			[ typesPath ]: {
				body: { post: { slug: 'post', rest_base: 'posts' } },
				headers: { Allow: 'GET' },
			},
			'/wp/v2/settings': { body: {} },
		};

		it( 'adds a post type missing from the preloaded types', () => {
			bridge.getGBKit.mockReturnValue( {
				post: {
					type: 'book',
					restBase: 'books',
					restNamespace: 'library/v1',
				},
			} );

			const result = withEditedPostType( preloadData );

			expect( result[ typesPath ] ).toEqual( {
				body: {
					post: { slug: 'post', rest_base: 'posts' },
					book: {
						name: 'book',
						slug: 'book',
						taxonomies: [],
						rest_base: 'books',
						rest_namespace: 'library/v1',
					},
				},
				headers: { Allow: 'GET' },
			} );
			expect( result[ '/wp/v2/settings' ] ).toBe(
				preloadData[ '/wp/v2/settings' ]
			);
			expect( preloadData[ typesPath ].body.book ).toBeUndefined();
		} );

		it( 'falls back to default restBase and restNamespace when omitted from the payload', () => {
			bridge.getGBKit.mockReturnValue( { post: { type: 'book' } } );

			const result = withEditedPostType( preloadData );

			expect( result[ typesPath ].body.book ).toMatchObject( {
				rest_base: 'posts',
				rest_namespace: 'wp/v2',
			} );
		} );

		it.each( [
			[
				'the post type is already preloaded',
				{ post: { type: 'post' } },
			],
			[ 'no post payload is present', {} ],
		] )( 'leaves the preload data unchanged when %s', ( _, gbkit ) => {
			bridge.getGBKit.mockReturnValue( gbkit );

			expect( withEditedPostType( preloadData ) ).toBe( preloadData );
		} );

		it( 'leaves the preload data unchanged when post types are not preloaded', () => {
			bridge.getGBKit.mockReturnValue( { post: { type: 'book' } } );
			const data = { '/wp/v2/settings': { body: {} } };

			expect( withEditedPostType( data ) ).toBe( data );
		} );
	} );

	describe( 'postTypesFallbackMiddleware', () => {
		const typesPath = '/wp/v2/types?context=view';

		it( 'answers a failed post types request with the built-in types', async () => {
			bridge.getGBKit.mockReturnValue( { post: { type: 'book' } } );
			const next = vi.fn( () =>
				Promise.reject( new Error( 'Offline' ) )
			);

			const types = await postTypesFallbackMiddleware(
				{ path: typesPath },
				next
			);

			expect( Object.keys( types ) ).toEqual(
				expect.arrayContaining( [
					'post',
					'page',
					'attachment',
					'wp_block',
					'book',
				] )
			);
			expect( logger.warn ).toHaveBeenCalled();
		} );

		it( 'returns the post types the site sends', async () => {
			const types = { post: { slug: 'post' } };
			const next = vi.fn( () => Promise.resolve( types ) );

			await expect(
				postTypesFallbackMiddleware( { path: typesPath }, next )
			).resolves.toBe( types );
		} );

		it.each( [
			[ 'other paths', { path: '/wp/v2/types/post?context=edit' } ],
			[ 'unparsed requests', { path: typesPath, parse: false } ],
		] )( 'lets failures of %s through', async ( _, options ) => {
			const failure = new Error( 'Offline' );
			const next = vi.fn( () => Promise.reject( failure ) );

			await expect(
				postTypesFallbackMiddleware( options, next )
			).rejects.toBe( failure );
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

		it( 'rejects at once when aborted while waiting to retry', async () => {
			const controller = new AbortController();
			global.fetch = vi.fn( () => rateLimited() );

			const request = apiFetch( {
				path: '/wp/v2/taxonomies',
				signal: controller.signal,
			} );
			const assertion = expect( request ).rejects.toMatchObject( {
				name: 'AbortError',
			} );
			await vi.advanceTimersByTimeAsync( 100 );
			controller.abort();
			await vi.advanceTimersByTimeAsync( 0 );

			expect( vi.getTimerCount() ).toBe( 0 );
			await assertion;
			expect( global.fetch ).toHaveBeenCalledTimes( 1 );
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

	describe( 'oEmbed responses', () => {
		const proxyPath =
			'/oembed/1.0/proxy?url=https%3A%2F%2Fvideopress.com%2Fv%2FeDeLfBNN';

		beforeEach( () => {
			bridge.getGBKit.mockReturnValue( {
				siteApiRoot: 'https://example.com/wp-json/',
				authHeader: 'Bearer test-token',
				siteApiNamespace: [],
				namespaceExcludedPaths: [],
			} );
		} );

		function respondWith( body, status = 200 ) {
			global.fetch = vi.fn( () =>
				Promise.resolve(
					new Response( JSON.stringify( body ), {
						status,
						headers: { 'Content-Type': 'application/json' },
					} )
				)
			);
		}

		it( 'rejects when WordPress cannot embed the URL', async () => {
			respondWith(
				{
					code: 'oembed_invalid_url',
					message: 'Not Found',
					data: { status: 404 },
				},
				404
			);

			await expect(
				apiFetch( { path: proxyPath } )
			).rejects.toMatchObject( { code: 'oembed_invalid_url' } );
		} );

		it( 'rejects when the request fails', async () => {
			global.fetch = vi.fn( () =>
				Promise.reject( new TypeError( 'Load failed' ) )
			);

			await expect(
				apiFetch( { path: proxyPath } )
			).rejects.toBeDefined();
		} );

		it( 'removes the wrapper around a provider iframe', async () => {
			respondWith( {
				html: '<span class="embed-youtube"><iframe src="https://www.youtube.com/embed/abc"></iframe></span>',
				type: 'video',
			} );

			const preview = await apiFetch( { path: proxyPath } );

			expect( preview.html ).toBe(
				'<iframe src="https://www.youtube.com/embed/abc"></iframe>'
			);
		} );

		it( 'returns other embed markup as WordPress sent it', async () => {
			const html =
				'<a href="https://example.com/post">https://example.com/post</a>';
			respondWith( { html, type: 'rich' } );

			const preview = await apiFetch( { path: proxyPath } );

			expect( preview ).toEqual( { html, type: 'rich' } );
		} );
	} );
} );
