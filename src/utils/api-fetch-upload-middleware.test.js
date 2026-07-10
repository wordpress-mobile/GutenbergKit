/**
 * External dependencies
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';

/**
 * Internal dependencies
 */
import { nativeMediaUploadMiddleware } from './api-fetch';

// Mock dependencies
vi.mock( './bridge', () => ( {
	getGBKit: vi.fn( () => ( {} ) ),
} ) );

vi.mock( './logger', () => ( {
	info: vi.fn(),
	warn: vi.fn(),
	error: vi.fn(),
} ) );

import { getGBKit } from './bridge';

function makeNext() {
	return vi.fn( () => Promise.resolve( { passthrough: true } ) );
}

function makePostMediaOptions( file ) {
	const body = new FormData();
	if ( file ) {
		body.append( 'file', file, file.name );
	}
	return {
		method: 'POST',
		path: '/wp/v2/media',
		body,
	};
}

function makeFile( name = 'photo.jpg', type = 'image/jpeg' ) {
	return new File( [ 'fake data' ], name, { type } );
}

describe( 'nativeMediaUploadMiddleware', () => {
	beforeEach( () => {
		vi.restoreAllMocks();
		global.fetch = vi.fn();
	} );

	// MARK: - Passthrough cases

	it( 'passes through when nativeUploadPort is not configured', () => {
		getGBKit.mockReturnValue( {} );
		const next = makeNext();

		nativeMediaUploadMiddleware( makePostMediaOptions( makeFile() ), next );

		expect( next ).toHaveBeenCalled();
		expect( global.fetch ).not.toHaveBeenCalled();
	} );

	it( 'passes through for non-POST requests', () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );
		const next = makeNext();

		nativeMediaUploadMiddleware(
			{ method: 'GET', path: '/wp/v2/media', body: new FormData() },
			next
		);

		expect( next ).toHaveBeenCalled();
		expect( global.fetch ).not.toHaveBeenCalled();
	} );

	it( 'passes through for non-media paths', () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );
		const next = makeNext();

		nativeMediaUploadMiddleware(
			{ method: 'POST', path: '/wp/v2/posts', body: new FormData() },
			next
		);

		expect( next ).toHaveBeenCalled();
		expect( global.fetch ).not.toHaveBeenCalled();
	} );

	it( 'passes through for media sub-paths like /wp/v2/media/123', () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );
		const next = makeNext();
		const body = new FormData();
		body.append( 'file', makeFile(), 'photo.jpg' );

		nativeMediaUploadMiddleware(
			{ method: 'POST', path: '/wp/v2/media/123', body },
			next
		);

		expect( next ).toHaveBeenCalled();
		expect( global.fetch ).not.toHaveBeenCalled();
	} );

	it( 'passes through for similarly-prefixed paths like /wp/v2/media-categories', () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );
		const next = makeNext();
		const body = new FormData();
		body.append( 'file', makeFile(), 'photo.jpg' );

		nativeMediaUploadMiddleware(
			{ method: 'POST', path: '/wp/v2/media-categories', body },
			next
		);

		expect( next ).toHaveBeenCalled();
		expect( global.fetch ).not.toHaveBeenCalled();
	} );

	it( 'passes through when body is not FormData', () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );
		const next = makeNext();

		nativeMediaUploadMiddleware(
			{ method: 'POST', path: '/wp/v2/media', body: '{}' },
			next
		);

		expect( next ).toHaveBeenCalled();
		expect( global.fetch ).not.toHaveBeenCalled();
	} );

	it( 'passes through when FormData has no file field', () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );
		const next = makeNext();
		const body = new FormData();
		body.append( 'title', 'no file here' );

		nativeMediaUploadMiddleware(
			{ method: 'POST', path: '/wp/v2/media', body },
			next
		);

		expect( next ).toHaveBeenCalled();
		expect( global.fetch ).not.toHaveBeenCalled();
	} );

	// MARK: - Interception

	it( 'intercepts POST /wp/v2/media with file and fetches to local server', async () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 12345,
			nativeUploadToken: 'test-token',
		} );
		const next = makeNext();

		global.fetch = vi.fn( () =>
			Promise.resolve( {
				ok: true,
				json: () =>
					Promise.resolve( {
						id: 42,
						url: 'https://example.com/photo.jpg',
						alt: '',
						caption: '',
						title: 'photo',
						mime: 'image/jpeg',
						type: 'image',
					} ),
			} )
		);

		await nativeMediaUploadMiddleware(
			makePostMediaOptions( makeFile() ),
			next
		);

		expect( next ).not.toHaveBeenCalled();
		expect( global.fetch ).toHaveBeenCalledOnce();

		const [ url, options ] = global.fetch.mock.calls[ 0 ];
		expect( url ).toBe( 'http://localhost:12345/upload' );
		expect( options.method ).toBe( 'POST' );
		expect( options.headers[ 'Relay-Authorization' ] ).toBe(
			'Bearer test-token'
		);
		expect( options.body ).toBeInstanceOf( FormData );
	} );

	it( 'forwards the original body and query to the native server', async () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 12345,
			nativeUploadToken: 'test-token',
		} );

		global.fetch = vi.fn( () =>
			Promise.resolve( {
				ok: true,
				json: () => Promise.resolve( { id: 1 } ),
			} )
		);

		const body = new FormData();
		body.append( 'file', makeFile(), 'photo.jpg' );
		body.append( 'post', '123' );

		await nativeMediaUploadMiddleware(
			{
				method: 'POST',
				path: '/wp/v2/media?_embed=wp:featuredmedia',
				body,
			},
			makeNext()
		);

		const [ url, fetchOptions ] = global.fetch.mock.calls[ 0 ];
		// The original query is appended so ?_embed reaches WordPress.
		expect( url ).toBe(
			'http://localhost:12345/upload?_embed=wp:featuredmedia'
		);
		// The original body is forwarded verbatim, so `post` survives.
		expect( fetchOptions.body ).toBe( body );
		expect( fetchOptions.body.get( 'post' ) ).toBe( '123' );
	} );

	it( 'returns the relayed WordPress attachment unchanged', async () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );

		// The native server relays WordPress's raw attachment response; the
		// middleware must return it verbatim, not reshape it — so consumers get
		// the real media_details.sizes, link, and raw/rendered fields.
		const attachment = {
			id: 77,
			source_url: 'https://example.com/image.jpg',
			alt_text: 'alt text',
			caption: { raw: 'a caption', rendered: 'a caption' },
			title: { raw: 'image', rendered: 'image' },
			mime_type: 'image/jpeg',
			media_type: 'image',
			media_details: {
				width: 4032,
				height: 3024,
				sizes: {
					large: {
						source_url: 'https://example.com/image-1024x768.jpg',
					},
				},
			},
			link: 'https://example.com/image/',
		};

		global.fetch = vi.fn( () =>
			Promise.resolve( {
				ok: true,
				json: () => Promise.resolve( attachment ),
			} )
		);

		const result = await nativeMediaUploadMiddleware(
			makePostMediaOptions( makeFile() ),
			makeNext()
		);

		expect( result ).toEqual( attachment );
	} );

	// MARK: - Error handling

	it( 'rejects with the WordPress error body on a non-ok response', async () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );

		// The native server relays WordPress's error status + JSON body; the
		// middleware rejects with that body as-is (like @wordpress/api-fetch) so
		// media-utils surfaces WordPress's real message.
		global.fetch = vi.fn( () =>
			Promise.resolve( {
				ok: false,
				status: 403,
				json: () =>
					Promise.resolve( {
						code: 'rest_cannot_create',
						message:
							'Sorry, you are not allowed to upload this file type.',
					} ),
			} )
		);

		await expect(
			nativeMediaUploadMiddleware(
				makePostMediaOptions( makeFile() ),
				makeNext()
			)
		).rejects.toMatchObject( {
			code: 'rest_cannot_create',
			message: expect.stringContaining( 'not allowed' ),
		} );
	} );

	it( 'rejects with invalid_json when the error body is not JSON', async () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );

		global.fetch = vi.fn( () =>
			Promise.resolve( {
				ok: false,
				status: 502,
				json: () =>
					Promise.reject( new SyntaxError( 'Unexpected token' ) ),
			} )
		);

		await expect(
			nativeMediaUploadMiddleware(
				makePostMediaOptions( makeFile() ),
				makeNext()
			)
		).rejects.toMatchObject( { code: 'invalid_json' } );
	} );

	it( 'falls back to the default upload path when the local server is unreachable', async () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );
		const next = makeNext();

		// A connection-level failure (server never started, restarted on a new
		// port, or torn down) rejects `fetch` with a TypeError.
		global.fetch = vi.fn( () =>
			Promise.reject( new TypeError( 'Failed to fetch' ) )
		);

		const result = await nativeMediaUploadMiddleware(
			makePostMediaOptions( makeFile() ),
			next
		);

		// The upload is not failed — it degrades to the default upload path.
		expect( next ).toHaveBeenCalledOnce();
		expect( result ).toEqual( { passthrough: true } );
	} );

	it( 'propagates an abort instead of falling back', async () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );
		const next = makeNext();

		const abortError = new Error( 'The operation was aborted.' );
		abortError.name = 'AbortError';
		global.fetch = vi.fn( () => Promise.reject( abortError ) );

		await expect(
			nativeMediaUploadMiddleware(
				makePostMediaOptions( makeFile() ),
				next
			)
		).rejects.toMatchObject( { name: 'AbortError' } );

		// An explicit cancellation must not be retried via the default path.
		expect( next ).not.toHaveBeenCalled();
	} );

	// MARK: - Signal forwarding

	it( 'forwards abort signal to fetch', async () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );

		global.fetch = vi.fn( () =>
			Promise.resolve( {
				ok: true,
				json: () =>
					Promise.resolve( {
						id: 1,
						url: '',
						title: '',
						mime: '',
						type: '',
					} ),
			} )
		);

		const controller = new AbortController();
		const options = makePostMediaOptions( makeFile() );
		options.signal = controller.signal;

		await nativeMediaUploadMiddleware( options, makeNext() );

		expect( global.fetch.mock.calls[ 0 ][ 1 ].signal ).toBe(
			controller.signal
		);
	} );
} );
