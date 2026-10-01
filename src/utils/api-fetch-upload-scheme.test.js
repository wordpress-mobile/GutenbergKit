/**
 * External dependencies
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';

/**
 * Internal dependencies
 */
import {
	nativeMediaUploadMiddleware,
	NATIVE_UPLOAD_CHUNK_SIZE,
} from './api-fetch';

vi.mock( './bridge', () => ( {
	getGBKit: vi.fn( () => ( {} ) ),
} ) );

vi.mock( './logger', () => ( {
	info: vi.fn(),
	warn: vi.fn(),
	error: vi.fn(),
} ) );

import { getGBKit } from './bridge';
import { warn } from './logger';

const BASE = 'gbk-upload://upload';
const SESSION = '0f8fad5b-d9cb-469f-a165-70867728950e';

function makeNext() {
	return vi.fn( () => Promise.resolve( { passthrough: true } ) );
}

function makeOptions( file, { path = '/wp/v2/media', fields = [] } = {} ) {
	const body = new FormData();
	for ( const [ name, value ] of fields ) {
		body.append( name, value );
	}
	body.append( 'file', file, file.name );
	return { method: 'POST', path, body };
}

function json( status, body, headers = {} ) {
	return new Response( JSON.stringify( body ), {
		status,
		headers: { 'Content-Type': 'application/json', ...headers },
	} );
}

/**
 * A fake native upload scheme: records every request and answers from `routes`,
 * keyed by the URL without the scheme base.
 *
 * @param {Object} routes Handlers keyed by path, e.g. `/sessions`.
 * @return {Array} The recorded requests.
 */
function installScheme( routes = {} ) {
	const requests = [];
	global.fetch = vi.fn( async ( url, init = {} ) => {
		const path = url.replace( BASE, '' );
		const request = { path, init };
		requests.push( request );
		const key = Object.keys( routes ).find( ( route ) =>
			new RegExp( `^${ route }$` ).test( path.split( '?' )[ 0 ] )
		);
		if ( key ) {
			return routes[ key ]( request );
		}
		if ( path === '/sessions' ) {
			return json( 201, { id: SESSION } );
		}
		if ( path.startsWith( `/sessions/${ SESSION }/chunks` ) ) {
			return json( 200, { received: 0 } );
		}
		if ( path === `/sessions/${ SESSION }/finish` ) {
			return json( 201, {
				id: 42,
				source_url: 'https://example.com/a.jpg',
			} );
		}
		if ( path === `/sessions/${ SESSION }/cancel` ) {
			return new Response( null, { status: 204 } );
		}
		return json( 404, { code: 'not_found' } );
	} );
	return requests;
}

describe( 'nativeMediaUploadMiddleware over the native upload scheme', () => {
	beforeEach( () => {
		vi.clearAllMocks();
		getGBKit.mockReturnValue( { nativeUploadScheme: 'gbk-upload' } );
	} );

	describe( 'page files', () => {
		it( 'sends the file in chunks, then finishes with its fields and query', async () => {
			const requests = installScheme();
			const size = NATIVE_UPLOAD_CHUNK_SIZE + 10;
			const file = new File( [ new Uint8Array( size ) ], 'big.mp4', {
				type: 'video/mp4',
			} );
			const options = makeOptions( file, {
				path: '/wp/v2/media?_embed=wp:featuredmedia',
				fields: [
					[ 'post', '7' ],
					[ 'field[]', 'a' ],
					[ 'field[]', 'b' ],
				],
			} );

			const result = await nativeMediaUploadMiddleware(
				options,
				makeNext()
			);

			expect( result ).toEqual( {
				id: 42,
				source_url: 'https://example.com/a.jpg',
			} );
			expect( requests.map( ( r ) => r.path ) ).toEqual( [
				'/sessions',
				`/sessions/${ SESSION }/chunks?offset=0`,
				`/sessions/${ SESSION }/chunks?offset=${ NATIVE_UPLOAD_CHUNK_SIZE }`,
				`/sessions/${ SESSION }/finish`,
			] );
			expect( JSON.parse( requests[ 0 ].init.body ) ).toEqual( {
				filename: 'big.mp4',
				mimeType: 'video/mp4',
				size,
			} );
			expect( requests[ 1 ].init.body.byteLength ).toBe(
				NATIVE_UPLOAD_CHUNK_SIZE
			);
			expect( requests[ 2 ].init.body.byteLength ).toBe( 10 );
			expect( JSON.parse( requests[ 3 ].init.body ) ).toEqual( {
				fields: [
					{ name: 'post', value: '7' },
					{ name: 'field[]', value: 'a' },
					{ name: 'field[]', value: 'b' },
				],
				query: '?_embed=wp:featuredmedia',
			} );
		} );

		it( 'finishes an empty file without sending a chunk', async () => {
			const requests = installScheme();
			const file = new File( [], 'empty.txt', { type: 'text/plain' } );

			await nativeMediaUploadMiddleware(
				makeOptions( file ),
				makeNext()
			);

			expect( requests.map( ( r ) => r.path ) ).toEqual( [
				'/sessions',
				`/sessions/${ SESSION }/finish`,
			] );
		} );

		it( 'passes the signal to every request', async () => {
			const requests = installScheme();
			const controller = new AbortController();
			const options = {
				...makeOptions( new File( [ 'x' ], 'a.jpg' ) ),
				signal: controller.signal,
			};

			await nativeMediaUploadMiddleware( options, makeNext() );

			for ( const request of requests ) {
				expect( request.init.signal ).toBe( controller.signal );
			}
		} );

		it( 'resolves with the raw Response under parse: false', async () => {
			installScheme();
			const options = {
				...makeOptions( new File( [ 'x' ], 'a.jpg' ) ),
				parse: false,
			};

			const response = await nativeMediaUploadMiddleware(
				options,
				makeNext()
			);

			expect( response ).toBeInstanceOf( Response );
			expect( response.status ).toBe( 201 );
		} );

		it( 'rejects with the Response under parse: false so core can recover post-processing', async () => {
			installScheme( {
				[ `/sessions/${ SESSION }/finish` ]: () =>
					json(
						500,
						{ code: 'rest_upload_sideload_error' },
						{ 'x-wp-upload-attachment-id': '99' }
					),
			} );
			const options = {
				...makeOptions( new File( [ 'x' ], 'a.jpg' ) ),
				parse: false,
			};

			const rejection = await nativeMediaUploadMiddleware(
				options,
				makeNext()
			).catch( ( error ) => error );

			expect( rejection ).toBeInstanceOf( Response );
			expect( rejection.headers.get( 'x-wp-upload-attachment-id' ) ).toBe(
				'99'
			);
		} );

		it( 'rejects with the parsed WordPress error by default', async () => {
			installScheme( {
				[ `/sessions/${ SESSION }/finish` ]: () =>
					json( 413, {
						code: 'rest_upload_file_too_big',
						message: 'Too big.',
					} ),
			} );

			await expect(
				nativeMediaUploadMiddleware(
					makeOptions( new File( [ 'x' ], 'a.jpg' ) ),
					makeNext()
				)
			).rejects.toEqual( {
				code: 'rest_upload_file_too_big',
				message: 'Too big.',
			} );
		} );
	} );

	describe( 'falling back before finish', () => {
		it( 'uploads through the web view when native uploads are unavailable', async () => {
			const requests = installScheme( {
				'/sessions': () =>
					json( 503, { code: 'native_upload_unavailable' } ),
			} );
			const next = makeNext();
			const options = makeOptions( new File( [ 'x' ], 'a.jpg' ) );

			const result = await nativeMediaUploadMiddleware( options, next );

			expect( result ).toEqual( { passthrough: true } );
			expect( next ).toHaveBeenCalledWith( options );
			expect( requests.map( ( r ) => r.path ) ).toEqual( [
				'/sessions',
			] );
			expect( warn ).toHaveBeenCalled();
		} );

		it( 'falls back when the scheme cannot be reached at all', async () => {
			global.fetch = vi.fn( () =>
				Promise.reject( new TypeError( 'Load failed' ) )
			);
			const next = makeNext();

			await nativeMediaUploadMiddleware(
				makeOptions( new File( [ 'x' ], 'a.jpg' ) ),
				next
			);

			expect( next ).toHaveBeenCalledTimes( 1 );
		} );

		it( 'cancels the session and falls back when a chunk fails', async () => {
			const requests = installScheme( {
				[ `/sessions/${ SESSION }/chunks` ]: () =>
					json( 409, { code: 'native_upload_offset_mismatch' } ),
			} );
			const next = makeNext();

			await nativeMediaUploadMiddleware(
				makeOptions( new File( [ 'x' ], 'a.jpg' ) ),
				next
			);

			expect( next ).toHaveBeenCalledTimes( 1 );
			expect( requests.map( ( r ) => r.path ) ).toContain(
				`/sessions/${ SESSION }/cancel`
			);
			expect( requests.map( ( r ) => r.path ) ).not.toContain(
				`/sessions/${ SESSION }/finish`
			);
		} );

		it( 'surfaces an abort during the chunks as the cancellation, without falling back', async () => {
			const controller = new AbortController();
			const reason = new DOMException( 'stop', 'AbortError' );
			const requests = installScheme( {
				[ `/sessions/${ SESSION }/chunks` ]: () => {
					controller.abort( reason );
					return Promise.reject( reason );
				},
			} );
			const next = makeNext();
			const options = {
				...makeOptions( new File( [ 'x' ], 'a.jpg' ) ),
				signal: controller.signal,
			};

			await expect(
				nativeMediaUploadMiddleware( options, next )
			).rejects.toBe( reason );
			expect( next ).not.toHaveBeenCalled();
			expect( requests.map( ( r ) => r.path ) ).toContain(
				`/sessions/${ SESSION }/cancel`
			);
		} );

		it( 'does not fall back once finish may have reached WordPress', async () => {
			installScheme( {
				[ `/sessions/${ SESSION }/finish` ]: () =>
					Promise.reject( new TypeError( 'Load failed' ) ),
			} );
			const next = makeNext();

			await expect(
				nativeMediaUploadMiddleware(
					makeOptions( new File( [ 'x' ], 'a.jpg' ) ),
					next
				)
			).rejects.toMatchObject( { code: 'fetch_error' } );
			expect( next ).not.toHaveBeenCalled();
		} );
	} );

	describe( 'transport selection and deletion', () => {
		it( 'prefers the scheme over a loopback server', async () => {
			getGBKit.mockReturnValue( {
				nativeUploadScheme: 'gbk-upload',
				nativeUploadPort: 8080,
				nativeUploadToken: 'token',
			} );
			const requests = installScheme();

			await nativeMediaUploadMiddleware(
				makeOptions( new File( [ 'x' ], 'a.jpg' ) ),
				makeNext()
			);

			expect( requests[ 0 ].path ).toBe( '/sessions' );
			expect( global.fetch.mock.calls[ 0 ][ 0 ] ).toMatch(
				/^gbk-upload:/
			);
		} );

		it( 'relays a media deletion with its query', async () => {
			const requests = installScheme( {
				'/media/42/delete': () => json( 200, { deleted: true } ),
			} );

			const result = await nativeMediaUploadMiddleware(
				{ method: 'DELETE', path: '/wp/v2/media/42?force=true' },
				makeNext()
			);

			expect( result ).toEqual( { deleted: true } );
			expect( requests[ 0 ].init.method ).toBe( 'POST' );
			expect( JSON.parse( requests[ 0 ].init.body ) ).toEqual( {
				query: '?force=true',
			} );
		} );

		it( 'passes through requests that are not media uploads', async () => {
			installScheme();
			const next = makeNext();

			await nativeMediaUploadMiddleware(
				{ method: 'GET', path: '/wp/v2/media' },
				next
			);

			expect( next ).toHaveBeenCalledTimes( 1 );
			expect( global.fetch ).not.toHaveBeenCalled();
		} );
	} );
} );
