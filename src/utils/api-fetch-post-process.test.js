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
import { error } from './logger';

vi.mock( './bridge', async ( importOriginal ) => {
	const actual = await importOriginal();
	return {
		...actual,
		getGBKit: vi.fn(),
	};
} );

vi.mock( './logger', () => ( {
	info: vi.fn(),
	error: vi.fn(),
	warn: vi.fn(),
	debug: vi.fn(),
} ) );

const SITE_API_ROOT = 'https://example.com/wp-json/';

/**
 * A `Response`-like object carrying the upload attachment ID header, which is
 * what core's middleware keys off to decide whether a failure is recoverable.
 *
 * @param {number}  status       The HTTP status.
 * @param {?string} attachmentId The `x-wp-upload-attachment-id` header value.
 * @param {Object}  body         The JSON body.
 * @return {Response} The response.
 */
function makeResponse( status, attachmentId, body = {} ) {
	const headers = { 'Content-Type': 'application/json' };
	if ( attachmentId ) {
		headers[ 'x-wp-upload-attachment-id' ] = attachmentId;
	}
	return new Response( JSON.stringify( body ), { status, headers } );
}

/** A media upload request, as `@wordpress/media-utils` issues it. */
function uploadOptions() {
	const body = new FormData();
	body.append(
		'file',
		new File( [ 'data' ], 'photo.jpg', { type: 'image/jpeg' } )
	);
	return { path: '/wp/v2/media', method: 'POST', body };
}

/**
 * The path of the Nth `fetch` call, normalized to a string.
 *
 * @param {number} index The zero-based call index.
 * @return {string} The requested URL.
 */
function fetchedPath( index ) {
	return String( global.fetch.mock.calls[ index ][ 0 ] );
}

describe( "core's media upload post-process middleware", () => {
	let originalFetch;

	beforeAll( () => {
		bridge.getGBKit.mockReturnValue( { siteApiRoot: SITE_API_ROOT } );
		configureApiFetch();
	} );

	beforeEach( () => {
		vi.clearAllMocks();
		originalFetch = global.fetch;
		bridge.getGBKit.mockReturnValue( {
			siteApiRoot: SITE_API_ROOT,
			authHeader: 'Bearer test-token',
			siteApiNamespace: [],
			namespaceExcludedPaths: [],
		} );
	} );

	afterEach( () => {
		global.fetch = originalFetch;
	} );

	it( 'retries post-process for an upload routed through the native server', async () => {
		// Regression test for middleware ordering. The native middleware handles
		// the upload without calling `next`, so core's middleware only ever sees
		// it by running *above* — registered after. With the two swapped, this
		// upload surfaces as a permanent failure and no post-process is issued.
		bridge.getGBKit.mockReturnValue( {
			siteApiRoot: SITE_API_ROOT,
			authHeader: 'Bearer test-token',
			siteApiNamespace: [],
			namespaceExcludedPaths: [],
			nativeUploadPort: 8080,
			nativeUploadToken: 'relay-token',
		} );

		global.fetch = vi.fn( ( url ) => {
			const path = String( url );
			if ( path.includes( 'post-process' ) ) {
				return Promise.resolve( makeResponse( 200, null, { id: 42 } ) );
			}
			// The native server relays WordPress's 500 plus the attachment ID.
			return Promise.resolve( makeResponse( 500, '42' ) );
		} );

		await expect( apiFetch( uploadOptions() ) ).resolves.toEqual( {
			id: 42,
		} );

		expect( fetchedPath( 0 ) ).toContain( 'localhost:8080/upload' );
		expect( fetchedPath( 1 ) ).toContain( '/wp/v2/media/42/post-process' );
	} );

	it( 'retries post-process when the upload fails with an attachment ID', async () => {
		global.fetch = vi.fn( ( url ) => {
			if ( String( url ).includes( 'post-process' ) ) {
				return Promise.resolve( makeResponse( 200, null, { id: 42 } ) );
			}
			return Promise.resolve( makeResponse( 500, '42' ) );
		} );

		// A recovered upload resolves with the post-process result rather than
		// surfacing the original 5xx to the block.
		await expect( apiFetch( uploadOptions() ) ).resolves.toEqual( {
			id: 42,
		} );

		expect( global.fetch ).toHaveBeenCalledTimes( 2 );
		expect( fetchedPath( 1 ) ).toContain( '/wp/v2/media/42/post-process' );
	} );

	it( 'deletes the orphaned attachment after exhausting retries', async () => {
		global.fetch = vi.fn( ( url ) => {
			const path = String( url );
			if ( path.includes( 'post-process' ) ) {
				return Promise.resolve( makeResponse( 500, null ) );
			}
			if ( path.includes( 'force=true' ) ) {
				return Promise.resolve(
					makeResponse( 200, null, { deleted: true } )
				);
			}
			return Promise.resolve( makeResponse( 500, '42' ) );
		} );

		await expect( apiFetch( uploadOptions() ) ).rejects.toBeDefined();

		const paths = global.fetch.mock.calls.map( ( [ url ] ) =>
			String( url )
		);
		// The initial upload, five post-process attempts, then the cleanup.
		expect(
			paths.filter( ( p ) => p.includes( 'post-process' ) )
		).toHaveLength( 5 );
		expect( paths.at( -1 ) ).toContain( '/wp/v2/media/42?force=true' );
	} );

	it( 'relays the orphan cleanup through the native server', async () => {
		// End-to-end shape of the `always` case on a native-upload host: the
		// upload fails, five post-process attempts fail, and the resulting
		// DELETE goes to the loopback server rather than direct to WordPress —
		// where a cross-origin editor's tunnelled DELETE would be blocked at
		// preflight, leaving the orphan behind.
		bridge.getGBKit.mockReturnValue( {
			siteApiRoot: SITE_API_ROOT,
			authHeader: 'Bearer test-token',
			siteApiNamespace: [],
			namespaceExcludedPaths: [],
			nativeUploadPort: 8080,
			nativeUploadToken: 'relay-token',
		} );

		global.fetch = vi.fn( ( url ) => {
			const path = String( url );
			if ( path.includes( 'post-process' ) ) {
				return Promise.resolve( makeResponse( 500, null ) );
			}
			if ( path.includes( '/media/42' ) ) {
				return Promise.resolve(
					makeResponse( 200, null, { deleted: true } )
				);
			}
			return Promise.resolve( makeResponse( 500, '42' ) );
		} );

		await expect( apiFetch( uploadOptions() ) ).rejects.toBeDefined();

		const paths = global.fetch.mock.calls.map( ( [ url ] ) =>
			String( url )
		);
		expect(
			paths.filter( ( p ) => p.includes( 'post-process' ) )
		).toHaveLength( 5 );
		expect( paths.at( -1 ) ).toBe(
			'http://localhost:8080/media/42?force=true'
		);
	} );

	it( 'authenticates the post-process retry', async () => {
		global.fetch = vi.fn( ( url ) => {
			if ( String( url ).includes( 'post-process' ) ) {
				return Promise.resolve( makeResponse( 200, null, { id: 42 } ) );
			}
			return Promise.resolve( makeResponse( 500, '42' ) );
		} );

		await expect( apiFetch( uploadOptions() ) ).resolves.toBeDefined();

		// The retry is issued through `next`, so it must still pick up the auth
		// header and the site API root from the middlewares below it.
		const [ url, options ] = global.fetch.mock.calls[ 1 ];
		expect( String( url ) ).toContain(
			`${ SITE_API_ROOT }wp/v2/media/42/post-process`
		);
		expect( options.headers.Authorization ).toBe( 'Bearer test-token' );
	} );

	it( 'does not retry when the failure carries no attachment ID', async () => {
		global.fetch = vi.fn( () =>
			Promise.resolve( makeResponse( 500, null ) )
		);

		await expect( apiFetch( uploadOptions() ) ).rejects.toBeDefined();

		expect( global.fetch ).toHaveBeenCalledTimes( 1 );
	} );

	it( 'leaves a successful upload untouched', async () => {
		global.fetch = vi.fn( () =>
			Promise.resolve(
				makeResponse( 201, null, { id: 42, source_url: 'x' } )
			)
		);

		await expect( apiFetch( uploadOptions() ) ).resolves.toEqual( {
			id: 42,
			source_url: 'x',
		} );

		expect( global.fetch ).toHaveBeenCalledTimes( 1 );
	} );

	it( 'does not log an error for an upload that recovers', async () => {
		// The initial 5xx is a handoff to core's post-process retry, not a
		// failure. A silently-recovered upload must surface no error to the host.
		bridge.getGBKit.mockReturnValue( {
			siteApiRoot: SITE_API_ROOT,
			authHeader: 'Bearer test-token',
			siteApiNamespace: [],
			namespaceExcludedPaths: [],
			nativeUploadPort: 8080,
			nativeUploadToken: 'relay-token',
		} );

		global.fetch = vi.fn( ( url ) => {
			if ( String( url ).includes( 'post-process' ) ) {
				return Promise.resolve( makeResponse( 200, null, { id: 42 } ) );
			}
			return Promise.resolve( makeResponse( 500, '42' ) );
		} );

		await expect( apiFetch( uploadOptions() ) ).resolves.toEqual( {
			id: 42,
		} );

		expect( error ).not.toHaveBeenCalled();
	} );
} );
