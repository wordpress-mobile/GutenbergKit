/**
 * External dependencies
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * Internal dependencies
 */
import {
	nativeMediaProcessingMiddleware,
	processFile,
} from './native-media-processing';

vi.mock( './bridge', () => ( {
	getGBKit: vi.fn( () => ( {} ) ),
} ) );

vi.mock( './logger', () => ( {
	error: vi.fn(),
	info: vi.fn(),
} ) );

import { getGBKit } from './bridge';

const encoder = new TextEncoder();

function makeFile( content = 'file', name = 'photo.jpg' ) {
	const file = new File( [ content ], name, { type: 'image/jpeg' } );
	file.arrayBuffer = () =>
		Promise.resolve( encoder.encode( content ).buffer );
	return file;
}

function installBridge( reply ) {
	const postMessage = vi.fn( reply );
	window.webkit = { messageHandlers: { mediaProcessing: { postMessage } } };
	return postMessage;
}

function installXMLHttpRequest( blob = new Blob( [ 'processed' ] ) ) {
	class Request {
		open = vi.fn();
		send = vi.fn( () => {
			this.status = 200;
			this.response = blob;
			this.onload();
		} );
		abort = vi.fn();
	}
	global.XMLHttpRequest = Request;
}

function mediaOptions( file, signal ) {
	const body = new FormData();
	body.append( 'post', '42' );
	body.append( 'caption', 'A caption' );
	body.append( 'file', file, file.name );
	return {
		method: 'POST',
		path: '/wp/v2/media?_embed=1',
		body,
		headers: { 'X-Test': 'yes' },
		signal,
	};
}

describe( 'native media processing', () => {
	beforeEach( () => {
		vi.restoreAllMocks();
		getGBKit.mockReturnValue( { nativeMediaProcessing: true } );
		installXMLHttpRequest();
	} );

	it( 'streams ordered 256 KiB chunks and preserves result metadata', async () => {
		const content = 'a'.repeat( 256 * 1024 + 2 );
		const postMessage = installBridge( ( message ) => {
			if ( message.action === 'begin' ) {
				return { accepted: true };
			}
			if ( message.action === 'finish' ) {
				return {
					url: 'gbk-processed-media://result',
					filename: 'scaled.jpg',
					mimeType: 'image/jpeg',
					size: 9,
				};
			}
			return {};
		} );

		const file = await processFile( makeFile( content ) );
		const messages = postMessage.mock.calls.map(
			( [ message ] ) => message
		);
		const chunks = messages.filter(
			( message ) => message.action === 'append'
		);

		expect( chunks ).toHaveLength( 2 );
		expect( chunks.map( ( chunk ) => chunk.offset ) ).toEqual( [
			0,
			256 * 1024,
		] );
		expect( atob( chunks[ 0 ].data ) ).toHaveLength( 256 * 1024 );
		expect( atob( chunks[ 1 ].data ) ).toHaveLength( 2 );
		expect( file.name ).toBe( 'scaled.jpg' );
		expect( file.type ).toBe( 'image/jpeg' );
		expect( messages.at( -1 ).action ).toBe( 'release' );
	} );

	it( 'bypasses processing when the native host declines', async () => {
		const postMessage = installBridge( () => ( { accepted: false } ) );
		const options = mediaOptions( makeFile() );
		const next = vi.fn( () => Promise.resolve( 'uploaded' ) );

		await expect(
			nativeMediaProcessingMiddleware( options, next )
		).resolves.toBe( 'uploaded' );
		expect( next ).toHaveBeenCalledWith( options );
		expect( postMessage ).toHaveBeenCalledTimes( 1 );
	} );

	it( 'replaces only the file and keeps request metadata', async () => {
		installBridge( ( message ) => {
			if ( message.action === 'begin' ) {
				return { accepted: true };
			}
			if ( message.action === 'finish' ) {
				return {
					url: 'gbk-processed-media://result',
					filename: 'processed.jpg',
					mimeType: 'image/jpeg',
					size: 9,
				};
			}
			return {};
		} );
		const options = mediaOptions( makeFile() );
		const next = vi.fn( () => Promise.resolve( 'uploaded' ) );

		await nativeMediaProcessingMiddleware( options, next );
		const forwarded = next.mock.calls[ 0 ][ 0 ];

		expect( forwarded ).not.toBe( options );
		expect( forwarded.body ).not.toBe( options.body );
		expect( forwarded.body.get( 'post' ) ).toBe( '42' );
		expect( forwarded.body.get( 'caption' ) ).toBe( 'A caption' );
		expect( forwarded.body.get( 'file' ).name ).toBe( 'processed.jpg' );
		expect( forwarded.headers ).toBe( options.headers );
		expect( forwarded.signal ).toBe( options.signal );
		expect( forwarded.path ).toBe( options.path );
	} );

	it( 'does not upload remotely when processing fails', async () => {
		installBridge( () => Promise.reject( new Error( 'native failed' ) ) );
		const next = vi.fn();

		await expect(
			nativeMediaProcessingMiddleware( mediaOptions( makeFile() ), next )
		).rejects.toEqual( {
			code: 'native_media_processing_error',
			message: 'native failed',
		} );
		expect( next ).not.toHaveBeenCalled();
	} );

	it( 'cancels promptly while finish is pending and preserves the abort reason', async () => {
		let resolveFinish;
		const finish = new Promise( ( resolve ) => {
			resolveFinish = resolve;
		} );
		const postMessage = installBridge( ( message ) => {
			if ( message.action === 'begin' ) {
				return { accepted: true };
			}
			if ( message.action === 'finish' ) {
				return finish;
			}
			return {};
		} );
		const controller = new AbortController();
		const reason = new DOMException( 'Stopped', 'AbortError' );
		const promise = processFile( makeFile(), controller.signal );
		const rejection = expect( promise ).rejects.toBe( reason );

		await vi.waitFor( () =>
			expect( postMessage ).toHaveBeenCalledWith(
				expect.objectContaining( { action: 'finish' } )
			)
		);
		controller.abort( reason );
		await vi.waitFor( () =>
			expect( postMessage ).toHaveBeenCalledWith(
				expect.objectContaining( { action: 'cancel' } )
			)
		);
		await rejection;
		resolveFinish( {
			url: 'gbk-processed-media://result',
			filename: 'processed.jpg',
			mimeType: 'image/jpeg',
		} );
	} );

	it( 'preserves a pre-aborted signal reason', async () => {
		const controller = new AbortController();
		const reason = new DOMException( 'Stopped', 'AbortError' );
		controller.abort( reason );
		const postMessage = installBridge( vi.fn() );

		await expect(
			processFile( makeFile(), controller.signal )
		).rejects.toBe( reason );
		expect( postMessage ).not.toHaveBeenCalled();
	} );

	it( 'rejects a truncated processed resource before remote upload', async () => {
		installBridge( ( message ) => {
			if ( message.action === 'begin' ) {
				return { accepted: true };
			}
			if ( message.action === 'finish' ) {
				return {
					url: 'gbk-processed-media://result',
					filename: 'processed.jpg',
					mimeType: 'image/jpeg',
					size: 10,
				};
			}
			return {};
		} );
		const next = vi.fn();

		await expect(
			nativeMediaProcessingMiddleware( mediaOptions( makeFile() ), next )
		).rejects.toMatchObject( {
			code: 'native_media_processing_error',
			message: 'Processed media size does not match the native result.',
		} );
		expect( next ).not.toHaveBeenCalled();
	} );
} );
