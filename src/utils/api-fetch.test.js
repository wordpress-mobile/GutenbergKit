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
		} catch ( error ) {
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
		} catch ( error ) {
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
		} catch ( error ) {
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
			} catch ( error ) {
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
			} catch ( error ) {
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
			expect( result ).toEqual( {
				home: 'https://example.com',
				url: 'https://example.com',
			} );
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
			} catch ( error ) {
				// Ignore errors from the actual fetch
			}

			expect( global.fetch ).toHaveBeenCalled();
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
		} catch ( error ) {
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
