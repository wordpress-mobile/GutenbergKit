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

	it( 'passes through when the file field is not a File (e.g. a string)', () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );
		const next = makeNext();
		const body = new FormData();
		body.append( 'file', 'not-a-file' );

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

	it( 'passes through when nativeUploadToken is not configured', () => {
		getGBKit.mockReturnValue( { nativeUploadPort: 8080 } );
		const next = makeNext();

		nativeMediaUploadMiddleware( makePostMediaOptions( makeFile() ), next );

		expect( next ).toHaveBeenCalled();
		expect( global.fetch ).not.toHaveBeenCalled();
	} );

	it.each( [
		// A bare trailing `?` carries no parameters. The native `query`
		// accessors normalize it away, so this side must too — otherwise the
		// upload server receives a `?` the two platforms agree cannot exist.
		[ '/wp/v2/media?', 'http://localhost:12345/upload' ],
		[ '/wp/v2/media', 'http://localhost:12345/upload' ],
	] )( 'normalizes the query of %s to %s', async ( path, expectedUrl ) => {
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

		await nativeMediaUploadMiddleware(
			{ method: 'POST', path, body },
			makeNext()
		);

		const [ url ] = global.fetch.mock.calls[ 0 ];
		expect( url ).toBe( expectedUrl );
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

	it( 'rejects with invalid_json when a 2xx response body is not JSON', async () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );

		// A successful status but a non-JSON body (e.g. an HTML error page from
		// an intermediary). json() rejects; the middleware must normalize it, not
		// surface a raw SyntaxError.
		global.fetch = vi.fn( () =>
			Promise.resolve( {
				ok: true,
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

	it( 'propagates an abort during the 2xx response body read instead of invalid_json', async () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );
		const next = makeNext();

		// Headers arrive (fetch resolves), but the user aborts before the body
		// finishes streaming — json() rejects while the signal is now aborted. The
		// middleware must surface the cancellation, not an "invalid response".
		const abortError = new DOMException( 'Aborted', 'AbortError' );
		const signal = { aborted: false, reason: undefined };
		const options = { ...makePostMediaOptions( makeFile() ), signal };
		global.fetch = vi.fn( () =>
			Promise.resolve( {
				ok: true,
				json: () => {
					signal.aborted = true;
					signal.reason = abortError;
					return Promise.reject( abortError );
				},
			} )
		);

		await expect(
			nativeMediaUploadMiddleware( options, next )
		).rejects.toBe( abortError );
		expect( next ).not.toHaveBeenCalled();
	} );

	it( 'propagates an abort during a non-2xx response body read instead of invalid_json', async () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );
		const next = makeNext();

		const abortError = new DOMException( 'Aborted', 'AbortError' );
		const signal = { aborted: false, reason: undefined };
		const options = { ...makePostMediaOptions( makeFile() ), signal };
		global.fetch = vi.fn( () =>
			Promise.resolve( {
				ok: false,
				json: () => {
					signal.aborted = true;
					signal.reason = abortError;
					return Promise.reject( abortError );
				},
			} )
		);

		await expect(
			nativeMediaUploadMiddleware( options, next )
		).rejects.toBe( abortError );
		expect( next ).not.toHaveBeenCalled();
	} );

	it( 'normalizes a transport failure to api-fetch’s error shape without retrying', async () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );
		const next = makeNext();

		// A connection-level failure — the loopback server died out-of-band after
		// a valid start (reachability is otherwise gated proactively upstream, so
		// an unreachable server never advertises a port to fetch).
		const connectionError = new TypeError( 'Failed to fetch' );
		global.fetch = vi.fn( () => Promise.reject( connectionError ) );

		const error = await nativeMediaUploadMiddleware(
			makePostMediaOptions( makeFile() ),
			next
		).catch( ( e ) => e );

		// Normalized to api-fetch's { code, message } shape (online → fetch_error),
		// not surfaced as the raw code-less TypeError, so consumers keying off
		// error.code behave the same as for a direct upload.
		expect( error ).not.toBe( connectionError );
		expect( error.code ).toBe( 'fetch_error' );
		expect( typeof error.message ).toBe( 'string' );
		expect( error.message.length ).toBeGreaterThan( 0 );

		// No silent fallback to a direct re-upload — retrying a non-idempotent
		// POST could duplicate the attachment.
		expect( next ).not.toHaveBeenCalled();
	} );

	it( 'normalizes an offline transport failure to offline_error', async () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );
		const next = makeNext();

		const onLineSpy = vi
			.spyOn( globalThis.navigator, 'onLine', 'get' )
			.mockReturnValue( false );
		try {
			global.fetch = vi.fn( () =>
				Promise.reject( new TypeError( 'Failed to fetch' ) )
			);

			const error = await nativeMediaUploadMiddleware(
				makePostMediaOptions( makeFile() ),
				next
			).catch( ( e ) => e );

			expect( error.code ).toBe( 'offline_error' );
			expect( next ).not.toHaveBeenCalled();
		} finally {
			onLineSpy.mockRestore();
		}
	} );

	it( 'propagates an abort instead of falling back', async () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );
		const next = makeNext();

		// The race the middleware guards against: the signal is aborted, but
		// `fetch` rejects with a *distinct* network error (a TypeError can win the
		// race with the abort). The middleware must rethrow the signal's canonical
		// reason, NOT the fetch rejection — otherwise a cancelled upload surfaces a
		// spurious transport-failure notice.
		const controller = new AbortController();
		controller.abort();
		const options = {
			...makePostMediaOptions( makeFile() ),
			signal: controller.signal,
		};
		const networkError = new TypeError( 'Failed to fetch' );
		global.fetch = vi.fn( () => Promise.reject( networkError ) );

		// The middleware rethrows the signal's canonical reason (not the fetch
		// rejection) and does not retry.
		await expect(
			nativeMediaUploadMiddleware( options, next )
		).rejects.toBe( controller.signal.reason );

		// An explicit cancellation must not be retried via the default path.
		expect( next ).not.toHaveBeenCalled();
	} );

	it( 'propagates a timeout cancellation (aborted signal, non-AbortError) instead of falling back', async () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );
		const next = makeNext();

		// `AbortSignal.timeout()` aborts its signal and rejects with a TimeoutError
		// (not an AbortError). A `name === 'AbortError'` check would miss it and
		// wrongly fall back; keying off `signal.aborted` catches it. As with a
		// plain abort, `fetch` may reject with a distinct network error that races
		// the timeout, so the middleware must still rethrow the signal's reason.
		const timeoutError = new Error( 'The operation timed out.' );
		timeoutError.name = 'TimeoutError';
		const options = {
			...makePostMediaOptions( makeFile() ),
			signal: { aborted: true, reason: timeoutError },
		};
		const networkError = new TypeError( 'Failed to fetch' );
		global.fetch = vi.fn( () => Promise.reject( networkError ) );

		await expect(
			nativeMediaUploadMiddleware( options, next )
		).rejects.toBe( timeoutError );

		// A timeout is a cancellation, not an unreachable server — do not retry.
		expect( next ).not.toHaveBeenCalled();
	} );

	it( 'throws a canonical AbortError when an aborted signal has no reason', async () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'token',
		} );
		const next = makeNext();

		// Some engines mark the signal aborted without populating `reason`. The
		// middleware must still reject with a real AbortError, not a thrown
		// `undefined` that upstream would surface as a spurious failure.
		const options = {
			...makePostMediaOptions( makeFile() ),
			signal: { aborted: true, reason: undefined },
		};
		global.fetch = vi.fn( () =>
			Promise.reject( new TypeError( 'Failed to fetch' ) )
		);

		const error = await nativeMediaUploadMiddleware( options, next ).catch(
			( thrown ) => thrown
		);
		expect( error ).not.toBeUndefined();
		expect( error?.name ).toBe( 'AbortError' );
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
