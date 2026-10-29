import { describe, it, expect, vi, beforeEach } from 'vitest';
import { nativeMediaUploadMiddleware } from './api-fetch';
import { getGBKit } from './bridge';

// Mock dependencies
vi.mock( './bridge', () => ( {
	getGBKit: vi.fn( () => ( {} ) ),
} ) );

vi.mock( './logger', () => ( {
	info: vi.fn(),
	warn: vi.fn(),
	error: vi.fn(),
} ) );

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

	// MARK: - Raw response passthrough

	describe( 'parse: false', () => {
		beforeEach( () => {
			getGBKit.mockReturnValue( {
				nativeUploadPort: 8080,
				nativeUploadToken: 'token',
			} );
		} );

		it( 'rejects with the Response so the attachment ID stays readable', async () => {
			// Core's media upload middleware needs the `Response` itself to read
			// `x-wp-upload-attachment-id` and retry post-process. Parsing the
			// body here would hide the header.
			const response = new Response( '{"code":"rest_upload_error"}', {
				status: 500,
				headers: { 'x-wp-upload-attachment-id': '4242' },
			} );
			global.fetch = vi.fn( () => Promise.resolve( response ) );

			const options = makePostMediaOptions( makeFile() );
			options.parse = false;

			const thrown = await nativeMediaUploadMiddleware(
				options,
				makeNext()
			).catch( ( error ) => error );

			expect( thrown ).toBe( response );
			expect( thrown.headers.get( 'x-wp-upload-attachment-id' ) ).toBe(
				'4242'
			);
		} );

		it( 'resolves with the Response on success', async () => {
			const response = new Response( '{"id":1}', { status: 201 } );
			global.fetch = vi.fn( () => Promise.resolve( response ) );

			const options = makePostMediaOptions( makeFile() );
			options.parse = false;

			await expect(
				nativeMediaUploadMiddleware( options, makeNext() )
			).resolves.toBe( response );
		} );
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

	// MARK: - Media deletion

	describe( 'media deletion', () => {
		beforeEach( () => {
			getGBKit.mockReturnValue( {
				nativeUploadPort: 8080,
				nativeUploadToken: 'token',
			} );
		} );

		it( 'routes an attachment deletion through the native server', async () => {
			// api-fetch tunnels DELETE as POST + `X-HTTP-Method-Override`, which
			// core's CORS allow-list omits, so a cross-origin editor cannot make
			// this request directly. Relaying it keeps the orphan cleanup working.
			global.fetch = vi.fn( () =>
				Promise.resolve(
					new Response( '{"deleted":true}', { status: 200 } )
				)
			);
			const next = makeNext();

			await expect(
				nativeMediaUploadMiddleware(
					{ method: 'DELETE', path: '/wp/v2/media/42?force=true' },
					next
				)
			).resolves.toEqual( { deleted: true } );

			expect( next ).not.toHaveBeenCalled();
			const [ url, options ] = global.fetch.mock.calls[ 0 ];
			expect( String( url ) ).toBe(
				'http://localhost:8080/media/42?force=true'
			);
			expect( options.method ).toBe( 'DELETE' );
			expect( options.headers[ 'Relay-Authorization' ] ).toBe(
				'Bearer token'
			);
		} );

		it( 'passes through a deletion of a non-media path', async () => {
			global.fetch = vi.fn();
			const next = makeNext();

			nativeMediaUploadMiddleware(
				{ method: 'DELETE', path: '/wp/v2/posts/42' },
				next
			);

			expect( next ).toHaveBeenCalled();
			expect( global.fetch ).not.toHaveBeenCalled();
		} );

		it( 'passes through the media collection path', async () => {
			// `/wp/v2/media` has no attachment ID, so it is not a deletion this
			// server relays.
			global.fetch = vi.fn();
			const next = makeNext();

			nativeMediaUploadMiddleware(
				{ method: 'DELETE', path: '/wp/v2/media' },
				next
			);

			expect( next ).toHaveBeenCalled();
			expect( global.fetch ).not.toHaveBeenCalled();
		} );

		it( 'passes through when the native server is not configured', async () => {
			getGBKit.mockReturnValue( {} );
			global.fetch = vi.fn();
			const next = makeNext();

			nativeMediaUploadMiddleware(
				{ method: 'DELETE', path: '/wp/v2/media/42?force=true' },
				next
			);

			expect( next ).toHaveBeenCalled();
			expect( global.fetch ).not.toHaveBeenCalled();
		} );

		it( 'rejects with the parsed error body on failure', async () => {
			global.fetch = vi.fn( () =>
				Promise.resolve(
					new Response( '{"code":"rest_cannot_delete"}', {
						status: 403,
					} )
				)
			);

			const thrown = await nativeMediaUploadMiddleware(
				{ method: 'DELETE', path: '/wp/v2/media/42?force=true' },
				makeNext()
			).catch( ( error ) => error );

			// As api-fetch does, an error body without `data` gains the status.
			expect( thrown ).toEqual( {
				code: 'rest_cannot_delete',
				data: { status: 403 },
			} );
		} );
	} );
} );
