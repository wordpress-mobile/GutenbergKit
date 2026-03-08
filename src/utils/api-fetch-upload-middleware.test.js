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
		expect( options.headers.Authorization ).toBe( 'Bearer test-token' );
		expect( options.body ).toBeInstanceOf( FormData );
	} );

	it( 'transforms native response to WordPress REST API shape', async () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );

		global.fetch = vi.fn( () =>
			Promise.resolve( {
				ok: true,
				json: () =>
					Promise.resolve( {
						id: 77,
						url: 'https://example.com/image.jpg',
						alt: 'alt text',
						caption: 'a caption',
						title: 'image',
						mime: 'image/jpeg',
						type: 'image',
					} ),
			} )
		);

		const result = await nativeMediaUploadMiddleware(
			makePostMediaOptions( makeFile() ),
			makeNext()
		);

		expect( result ).toEqual( {
			id: 77,
			source_url: 'https://example.com/image.jpg',
			alt_text: 'alt text',
			caption: { raw: 'a caption', rendered: 'a caption' },
			title: { raw: 'image', rendered: 'image' },
			mime_type: 'image/jpeg',
			media_type: 'image',
			link: 'https://example.com/image.jpg',
		} );
	} );

	it( 'handles missing optional fields in native response', async () => {
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
						url: 'https://example.com/file.pdf',
						title: 'file',
						mime: 'application/pdf',
						type: 'application',
					} ),
			} )
		);

		const result = await nativeMediaUploadMiddleware(
			makePostMediaOptions( makeFile( 'file.pdf', 'application/pdf' ) ),
			makeNext()
		);

		expect( result.alt_text ).toBe( '' );
		expect( result.caption ).toEqual( { raw: '', rendered: '' } );
	} );

	// MARK: - Error handling

	it( 'throws on non-ok response from local server', async () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );

		global.fetch = vi.fn( () =>
			Promise.resolve( {
				ok: false,
				status: 500,
				statusText: 'Internal Server Error',
				text: () => Promise.resolve( 'Server crashed' ),
			} )
		);

		await expect(
			nativeMediaUploadMiddleware(
				makePostMediaOptions( makeFile() ),
				makeNext()
			)
		).rejects.toMatchObject( {
			code: 'upload_failed',
			message: expect.stringContaining( '500' ),
		} );
	} );

	it( 'throws on fetch network error', async () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );

		global.fetch = vi.fn( () =>
			Promise.reject( new Error( 'Failed to fetch' ) )
		);

		await expect(
			nativeMediaUploadMiddleware(
				makePostMediaOptions( makeFile() ),
				makeNext()
			)
		).rejects.toBeDefined();
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
