import { Blob as NodeBlob } from 'node:buffer';
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
	createRelayXMLHttpRequest,
	installXMLHttpRequestRelay,
} from './xhr-relay';
import { getGBKit } from './bridge';

vi.mock( './bridge', () => ( {
	getGBKit: vi.fn(),
} ) );

/**
 * The body reads the relay has started, so a test can wait for them to finish.
 */
const { bodyReads } = vi.hoisted( () => ( { bodyReads: [] } ) );

vi.mock( './fetch-relay', async ( importOriginal ) => {
	const actual = await importOriginal();
	return {
		...actual,
		bufferedBody: ( ...args ) => {
			const read = actual.bufferedBody( ...args );
			bodyReads.push( read );
			return read;
		},
	};
} );

vi.mock( './logger', () => ( {
	debug: vi.fn(),
	info: vi.fn(),
	warn: vi.fn(),
	error: vi.fn(),
} ) );

const ENDPOINT = 'gbk-rest://relay/fetch';
const REST_RELAY = { endpoint: ENDPOINT };

/**
 * The relay URL a request is sent to.
 *
 * @param {string} url The request's URL.
 * @return {string} The relay's URL for it.
 */
function relayed( url ) {
	return `${ ENDPOINT }?url=${ encodeURIComponent( url ) }`;
}

/**
 * Stands in for the browser's `XMLHttpRequest`, recording what reaches it.
 */
class FakeXMLHttpRequest extends EventTarget {
	readyState = 0;

	timeout = 0;

	responseType = '';

	calls = [];

	#upload = new EventTarget();

	#withCredentials = false;

	open( ...args ) {
		this.calls.push( [ 'open', ...args ] );
		this.readyState = 1;
	}

	setRequestHeader( ...args ) {
		this.calls.push( [ 'setRequestHeader', ...args ] );
	}

	send( ...args ) {
		this.calls.push( [ 'send', ...args ] );
	}

	abort() {
		this.calls.push( [ 'abort' ] );
		this.readyState = 0;
	}

	// An accessor on the prototype, as the browser's is.
	get upload() {
		return this.#upload;
	}

	get withCredentials() {
		return this.#withCredentials;
	}

	set withCredentials( value ) {
		this.calls.push( [ 'withCredentials', value ] );
		this.#withCredentials = value;
	}

	get responseURL() {
		return this.calls.some( ( [ name ] ) => name === 'send' )
			? this.calls.find( ( [ name ] ) => name === 'open' )[ 2 ]
			: '';
	}

	/** Moves to `HEADERS_RECEIVED`, as the browser does when the response arrives. */
	receiveHeaders() {
		this.readyState = 2;
		this.dispatchEvent( new Event( 'readystatechange' ) );
	}

	/**
	 * The calls of one kind.
	 *
	 * @param {string} name The method or property.
	 * @return {Array} Each call's arguments.
	 */
	callsTo( name ) {
		return this.calls
			.filter( ( [ called ] ) => called === name )
			.map( ( [ , ...args ] ) => args );
	}
}

/**
 * A jsdom `Blob`'s contents as text.
 *
 * @param {Blob} blob The blob.
 * @return {Promise<string>} Its text.
 */
function text( blob ) {
	return new Promise( ( resolve, reject ) => {
		const reader = new FileReader();
		reader.onload = () => resolve( reader.result );
		reader.onerror = () => reject( reader.error );
		reader.readAsText( blob );
	} );
}

/**
 * Lets every pending body read finish, and the relay act on it.
 *
 * Waits for the reads themselves, not a set number of timer turns: a read can
 * take more than one turn when other reads are running, as in a full test run.
 */
async function settle() {
	await Promise.allSettled( bodyReads );
	await new Promise( ( resolve ) => setTimeout( resolve ) );
}

describe( 'createRelayXMLHttpRequest', () => {
	const RelayXMLHttpRequest = createRelayXMLHttpRequest( FakeXMLHttpRequest, {
		restRelay: REST_RELAY,
	} );

	describe( 'requests it relays', () => {
		it( 'opens another origin through the relay, with its URL', () => {
			const xhr = new RelayXMLHttpRequest();
			const url = 'https://example.com/wp-admin/admin-ajax.php?x=1';
			xhr.open( 'POST', url );

			expect( xhr.callsTo( 'open' ) ).toEqual( [
				[ 'POST', relayed( url ) ],
			] );
		} );

		it( 'keeps the arguments after the URL as they were passed', () => {
			// `open( m, u )` is asynchronous; `open( m, u, undefined )` is not.
			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'GET', 'https://example.org/a', undefined );

			expect( xhr.callsTo( 'open' ) ).toEqual( [
				[ 'GET', relayed( 'https://example.org/a' ), undefined ],
			] );
		} );

		it( 'is still an XMLHttpRequest', () => {
			expect( new RelayXMLHttpRequest() ).toBeInstanceOf(
				FakeXMLHttpRequest
			);
			expect( RelayXMLHttpRequest.name ).toBe( 'XMLHttpRequest' );
		} );

		it( 'sends a string body and its headers as they are', () => {
			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'POST', 'https://example.com/wp-admin/admin-ajax.php' );
			xhr.setRequestHeader( 'Authorization', 'Bearer own-token' );
			xhr.setRequestHeader(
				'Content-Type',
				'application/x-www-form-urlencoded'
			);
			xhr.send( 'action=x' );

			expect( xhr.callsTo( 'setRequestHeader' ) ).toEqual( [
				[ 'Authorization', 'Bearer own-token' ],
				[ 'Content-Type', 'application/x-www-form-urlencoded' ],
			] );
			expect( xhr.callsTo( 'send' ) ).toEqual( [ [ 'action=x' ] ] );
		} );

		it( 'reads a Blob into an ArrayBuffer before sending it', async () => {
			// tus-js-client sends each chunk of an upload as a `Blob` slice.
			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'PATCH', 'https://example.org/files/abc' );
			xhr.setRequestHeader(
				'Content-Type',
				'application/offset+octet-stream'
			);
			xhr.send( new NodeBlob( [ 'chunk bytes' ] ) );

			expect( xhr.callsTo( 'send' ) ).toEqual( [] );
			await settle();

			const [ [ body ] ] = xhr.callsTo( 'send' );
			expect( body ).toBeInstanceOf( ArrayBuffer );
			expect( new TextDecoder().decode( body ) ).toBe( 'chunk bytes' );
			expect( xhr.callsTo( 'setRequestHeader' ) ).toEqual( [
				[ 'Content-Type', 'application/offset+octet-stream' ],
			] );
		} );

		it( 'gives a Blob without a Content-Type its own type', async () => {
			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'POST', 'https://example.org/upload' );
			xhr.send( new NodeBlob( [ '{}' ], { type: 'application/json' } ) );
			await settle();

			expect( xhr.callsTo( 'setRequestHeader' ) ).toEqual( [
				[ 'Content-Type', 'application/json' ],
			] );
		} );

		it( 'serializes FormData, and takes the boundary from the serialization', async () => {
			// jsdom's `FormData` and Node's `Response` don't interoperate, so
			// the browser's serialization is stood in for.
			const serialized = new TextEncoder().encode( '--xyz multipart' );
			vi.stubGlobal(
				'Response',
				class {
					headers = new Headers( {
						'Content-Type': 'multipart/form-data; boundary=xyz',
					} );
					arrayBuffer() {
						return Promise.resolve( serialized.buffer );
					}
				}
			);
			const form = new FormData();
			form.append( 'title', 'Hello' );

			const xhr = new RelayXMLHttpRequest();
			try {
				xhr.open( 'POST', 'https://example.com/wp-json/wp/v2/media' );
				// A stale type, as a caller copying headers would send.
				xhr.setRequestHeader( 'Content-Type', 'multipart/form-data' );
				xhr.send( form );
				await settle();
			} finally {
				vi.unstubAllGlobals();
			}

			expect( xhr.callsTo( 'send' ) ).toEqual( [
				[ serialized.buffer ],
			] );
			expect( xhr.callsTo( 'setRequestHeader' ) ).toEqual( [
				[ 'Content-Type', 'multipart/form-data; boundary=xyz' ],
			] );
		} );

		it( 'reads a Blob another window made, which is not an instance of this one', async () => {
			const foreign = new NodeBlob( [ 'chunk bytes' ] );
			expect( foreign ).not.toBeInstanceOf( Blob );

			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'POST', 'https://example.org/upload' );
			xhr.send( foreign );
			await settle();

			expect( xhr.callsTo( 'send' )[ 0 ][ 0 ] ).toBeInstanceOf(
				ArrayBuffer
			);
		} );

		it( 'sends an ArrayBuffer, which WebKit delivers, without waiting', () => {
			const body = new ArrayBuffer( 4 );
			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'POST', 'https://example.org/upload' );
			xhr.send( body );

			expect( xhr.callsTo( 'send' ) ).toEqual( [ [ body ] ] );
		} );

		describe( 'synchronous requests', () => {
			// A synchronous request can't wait for a `Blob` to be read, so the
			// relay reads it with a synchronous request for a `blob:` URL.
			let blobs;
			let reads;
			let Relay;

			beforeEach( () => {
				blobs = new Map();
				reads = new Map();
				URL.createObjectURL = vi.fn( ( blob ) => {
					const url = `blob:null/${ blobs.size }`;
					blobs.set( url, blob );
					return url;
				} );
				URL.revokeObjectURL = vi.fn( ( url ) => blobs.delete( url ) );

				class ReadingXMLHttpRequest extends FakeXMLHttpRequest {
					responseText = '';

					overrideMimeType( type ) {
						this.calls.push( [ 'overrideMimeType', type ] );
					}

					send( ...args ) {
						super.send( ...args );
						const [ , , url ] = this.calls.find(
							( [ name ] ) => name === 'open'
						);
						if ( url.startsWith( 'blob:' ) ) {
							const read = reads.get( blobs.get( url ) ) ?? '';
							if ( read instanceof Error ) {
								throw read;
							}
							this.responseText = read;
						}
					}
				}
				Relay = createRelayXMLHttpRequest( ReadingXMLHttpRequest, {
					restRelay: REST_RELAY,
				} );
			} );

			afterEach( () => {
				delete URL.createObjectURL;
				delete URL.revokeObjectURL;
			} );

			it( 'reads a Blob before sending it, with its type', () => {
				const body = new Blob( [ 'ignored' ], { type: 'image/png' } );
				// What `x-user-defined` decodes the bytes 0x00 0x41 0x80 0xFF to.
				reads.set( body, '\u0000A\uF780\uF7FF' );

				const xhr = new Relay();
				xhr.open( 'POST', 'https://example.org/upload', false );
				xhr.send( body );

				const [ [ sent ] ] = xhr.callsTo( 'send' );
				expect( Array.from( new Uint8Array( sent ) ) ).toEqual( [
					0x00, 0x41, 0x80, 0xff,
				] );
				expect( xhr.callsTo( 'setRequestHeader' ) ).toEqual( [
					[ 'Content-Type', 'image/png' ],
				] );
				expect( blobs.size ).toBe( 0 );
			} );

			it( 'keeps the caller’s Content-Type for a Blob', () => {
				const body = new Blob( [ 'x' ], { type: 'image/png' } );

				const xhr = new Relay();
				xhr.open( 'PATCH', 'https://example.org/files/abc', false );
				xhr.setRequestHeader(
					'Content-Type',
					'application/offset+octet-stream'
				);
				xhr.send( body );

				expect( xhr.callsTo( 'setRequestHeader' ) ).toEqual( [
					[ 'Content-Type', 'application/offset+octet-stream' ],
				] );
			} );

			it( 'serializes FormData as multipart/form-data, with its files', async () => {
				const form = new FormData();
				form.append( 'title', 'Hello\nWorld' );
				form.append( 'a"b', 'x' );
				form.append(
					'file',
					new Blob( [ 'abc' ], { type: 'text/plain' } ),
					'a.txt'
				);
				let multipart;
				URL.createObjectURL.mockImplementationOnce( ( blob ) => {
					multipart = blob;
					return 'blob:null/form';
				} );

				const xhr = new Relay();
				xhr.open( 'POST', 'https://example.org/upload', false );
				// A stale type, as a caller copying headers would send.
				xhr.setRequestHeader( 'Content-Type', 'multipart/form-data' );
				xhr.send( form );

				const [ [ , type ] ] = xhr.callsTo( 'setRequestHeader' );
				const boundary = type.match(
					/^multipart\/form-data; boundary=(----WebKitFormBoundary[A-Za-z0-9]{16})$/
				)?.[ 1 ];
				expect( boundary ).toBeDefined();
				expect( await text( multipart ) ).toBe(
					[
						`--${ boundary }`,
						'Content-Disposition: form-data; name="title"',
						'',
						'Hello\r\nWorld',
						`--${ boundary }`,
						'Content-Disposition: form-data; name="a%22b"',
						'',
						'x',
						`--${ boundary }`,
						'Content-Disposition: form-data; name="file"; filename="a.txt"',
						'Content-Type: text/plain',
						'',
						'abc',
						`--${ boundary }--`,
						'',
					].join( '\r\n' )
				);
			} );

			it( 'fails as a network error when the body can’t be read', () => {
				const body = new Blob( [ 'x' ] );
				reads.set( body, new Error( 'gone' ) );

				const xhr = new Relay();
				xhr.open( 'POST', 'https://example.org/upload', false );

				expect( () => xhr.send( body ) ).toThrow(
					expect.objectContaining( { name: 'NetworkError' } )
				);
				expect(
					xhr.calls.filter(
						( [ name, , url ] ) =>
							name === 'open' && url.startsWith( 'blob:' )
					)
				).toEqual( [] );
				expect( xhr.callsTo( 'send' ) ).toEqual( [] );
				expect( blobs.size ).toBe( 0 );
			} );
		} );

		it( 'drops the body of a GET, as XMLHttpRequest does', () => {
			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'get', 'https://example.org/a' );
			xhr.send( new NodeBlob( [ 'x' ] ) );

			expect( xhr.callsTo( 'send' ) ).toEqual( [ [ null ] ] );
		} );
	} );

	describe( 'timeout', () => {
		it( 'tells native code the timeout, which WebKit does not apply', () => {
			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'GET', 'https://example.org/a' );
			xhr.timeout = 500;
			xhr.send();

			expect( xhr.callsTo( 'setRequestHeader' ) ).toEqual( [
				[ 'X-GBK-Relay-Timeout', '500' ],
			] );
		} );

		it( 'counts the time spent reading the body', async () => {
			vi.useFakeTimers( { toFake: [ 'Date' ] } );
			const xhr = new RelayXMLHttpRequest();
			try {
				xhr.open( 'POST', 'https://example.org/upload' );
				xhr.timeout = 500;
				xhr.send( new NodeBlob( [ 'x' ] ) );
				vi.setSystemTime( Date.now() + 200 );
				await settle();
			} finally {
				vi.useRealTimers();
			}

			expect( xhr.callsTo( 'setRequestHeader' ) ).toContainEqual( [
				'X-GBK-Relay-Timeout',
				'300',
			] );
		} );

		it( 'sends no timeout when there is none', () => {
			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'GET', 'https://example.org/a' );
			xhr.send();

			expect( xhr.callsTo( 'setRequestHeader' ) ).toEqual( [] );
		} );
	} );

	describe( 'upload events', () => {
		/**
		 * The upload events a request fires, with their sizes.
		 *
		 * @param {XMLHttpRequest} xhr The request.
		 * @return {Array} Each event's type, `loaded` and `total`.
		 */
		function recordUpload( xhr ) {
			const events = [];
			for ( const type of [ 'progress', 'load', 'loadend' ] ) {
				xhr.upload.addEventListener( type, ( event ) =>
					events.push( [ type, event.loaded, event.total ] )
				);
			}
			xhr.addEventListener( 'readystatechange', () =>
				events.push( [ 'readystatechange', xhr.readyState ] )
			);
			return events;
		}

		it( 'finishes the upload when the headers arrive, before the caller hears of them', () => {
			// WebKit fires none of these for a request native code answers.
			const xhr = new RelayXMLHttpRequest();
			const events = recordUpload( xhr );
			xhr.open( 'POST', 'https://example.org/upload' );
			xhr.send( 'héllo' );
			xhr.receiveHeaders();

			expect( events ).toEqual( [
				[ 'progress', 6, 6 ],
				[ 'load', 6, 6 ],
				[ 'loadend', 6, 6 ],
				[ 'readystatechange', 2 ],
			] );
		} );

		it( 'gives the size of a body read before sending', async () => {
			const xhr = new RelayXMLHttpRequest();
			const events = recordUpload( xhr );
			xhr.open( 'PATCH', 'https://example.org/files/abc' );
			xhr.send( new NodeBlob( [ 'chunk bytes' ] ) );
			await settle();
			xhr.receiveHeaders();

			expect( events[ 0 ] ).toEqual( [ 'progress', 11, 11 ] );
		} );

		it( 'fires none for a request without a body', () => {
			const xhr = new RelayXMLHttpRequest();
			const events = recordUpload( xhr );
			xhr.open( 'GET', 'https://example.org/a' );
			xhr.send();
			xhr.receiveHeaders();

			expect( events ).toEqual( [ [ 'readystatechange', 2 ] ] );
		} );

		it.each( [
			[ 'an empty string', () => '' ],
			[ 'an empty ArrayBuffer', () => new ArrayBuffer( 0 ) ],
			[ 'an empty Blob', () => new NodeBlob( [] ) ],
		] )( 'fires none for %s', async ( _, body ) => {
			// WebKit fires only the upload's `loadstart` for an empty body.
			const xhr = new RelayXMLHttpRequest();
			const events = recordUpload( xhr );
			xhr.open( 'POST', 'https://example.org/a' );
			xhr.send( body() );
			await settle();
			xhr.receiveHeaders();

			expect( events ).toEqual( [ [ 'readystatechange', 2 ] ] );
		} );

		it( 'keeps the browser from firing the upload\u2019s end again', () => {
			// WebKit counts the upload as unfinished, so an abort, timeout or
			// error after the headers would end it a second time.
			const xhr = new RelayXMLHttpRequest();
			const events = recordUpload( xhr );
			xhr.upload.addEventListener( 'abort', () =>
				events.push( [ 'abort' ] )
			);
			xhr.open( 'POST', 'https://example.org/upload' );
			xhr.send( 'x' );
			xhr.receiveHeaders();
			xhr.upload.dispatchEvent( new ProgressEvent( 'abort' ) );
			xhr.upload.dispatchEvent( new ProgressEvent( 'loadend' ) );

			expect( events ).toEqual( [
				[ 'progress', 1, 1 ],
				[ 'load', 1, 1 ],
				[ 'loadend', 1, 1 ],
				[ 'readystatechange', 2 ],
			] );
		} );

		it( 'lets the browser end the upload of a request opened again', () => {
			const xhr = new RelayXMLHttpRequest();
			const events = recordUpload( xhr );
			xhr.open( 'POST', 'https://example.org/upload' );
			xhr.send( 'x' );
			xhr.receiveHeaders();
			xhr.open( 'POST', 'https://example.org/upload' );
			xhr.send( 'x' );
			events.length = 0;
			xhr.upload.dispatchEvent( new ProgressEvent( 'loadend' ) );

			expect( events ).toEqual( [ [ 'loadend', 0, 0 ] ] );
		} );

		it( 'stops at progress when a listener aborts there', () => {
			// The browser fires the upload's abort instead of its load.
			const xhr = new RelayXMLHttpRequest();
			const events = recordUpload( xhr );
			xhr.upload.addEventListener( 'progress', () => xhr.abort(), {
				once: true,
			} );
			xhr.open( 'POST', 'https://example.org/upload' );
			xhr.send( 'x' );
			xhr.receiveHeaders();

			expect( events ).toEqual( [ [ 'progress', 1, 1 ] ] );
		} );

		it( 'hides the response from a caller that aborts on the upload\u2019s load', () => {
			// The browser fires it before any of the response arrives.
			class ArrivingXMLHttpRequest extends FakeXMLHttpRequest {
				get responseText() {
					return 'arrived anyway';
				}

				get responseURL() {
					return relayed( 'https://example.org/upload' );
				}
			}
			const Relay = createRelayXMLHttpRequest( ArrivingXMLHttpRequest, {
				restRelay: REST_RELAY,
			} );
			const xhr = new Relay();
			const events = recordUpload( xhr );
			xhr.upload.addEventListener( 'load', () => xhr.abort() );
			xhr.open( 'POST', 'https://example.org/upload' );
			xhr.send( 'x' );
			xhr.receiveHeaders();

			expect( events ).toEqual( [
				[ 'progress', 1, 1 ],
				[ 'load', 1, 1 ],
				[ 'loadend', 1, 1 ],
			] );
			expect( xhr.responseText ).toBe( '' );
			expect( xhr.response ).toBe( '' );
			expect( xhr.responseURL ).toBe( '' );
		} );

		it( 'fires none for a request that is not relayed', () => {
			const xhr = new RelayXMLHttpRequest();
			const events = recordUpload( xhr );
			xhr.open( 'POST', 'gbk-upload://upload/sessions' );
			xhr.send( '{}' );
			xhr.receiveHeaders();

			expect( events ).toEqual( [ [ 'readystatechange', 2 ] ] );
		} );
	} );

	describe( 'withCredentials', () => {
		it( 'sends a relayed request without cookies, but reads back as set', () => {
			// The relay answers `Access-Control-Allow-Origin: *`, which a
			// browser refuses to pair with a credentialed request.
			const xhr = new RelayXMLHttpRequest();
			xhr.withCredentials = true;
			xhr.open( 'GET', 'https://example.org/a' );

			expect( xhr.withCredentials ).toBe( true );
			expect( xhr.callsTo( 'withCredentials' ).at( -1 ) ).toEqual( [
				false,
			] );
		} );

		it( 'can be set again after an abort', async () => {
			// `abort()` leaves the request unsent, where the browser allows it.
			for ( const body of [ 'x', new NodeBlob( [ 'x' ] ) ] ) {
				const xhr = new RelayXMLHttpRequest();
				xhr.open( 'POST', 'https://example.org/upload' );
				xhr.send( body );
				xhr.abort();
				await settle();

				expect( () => {
					xhr.withCredentials = true;
				} ).not.toThrow();
				expect( xhr.withCredentials ).toBe( true );
			}
		} );

		it( 'keeps the caller’s value for a request that isn’t relayed', () => {
			const xhr = new RelayXMLHttpRequest();
			xhr.withCredentials = true;
			xhr.open( 'GET', 'gbk-upload://upload/sessions' );

			expect( xhr.callsTo( 'withCredentials' ).at( -1 ) ).toEqual( [
				true,
			] );
		} );
	} );

	describe( 'responseURL', () => {
		it( 'is the URL the caller opened, without its fragment', () => {
			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'GET', 'https://example.org/a?b=1#c' );
			expect( xhr.responseURL ).toBe( '' );

			xhr.send();
			expect( xhr.responseURL ).toBe( 'https://example.org/a?b=1' );
		} );
	} );

	describe( 'aborting while a body is read', () => {
		it( 'never sends the body, and ends the request with an abort', async () => {
			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'POST', 'https://example.org/upload' );
			xhr.send( new NodeBlob( [ 'x' ] ) );
			xhr.abort();
			await settle();

			// The browser only fires a request's events for one it sent, so a
			// `data:` request stands in for it and is aborted at once.
			expect( xhr.calls.slice( -3 ) ).toEqual( [
				[ 'open', 'POST', 'data:,' ],
				[ 'send', '' ],
				[ 'abort' ],
			] );
			expect( xhr.callsTo( 'send' ) ).toEqual( [ [ '' ] ] );
		} );

		it( 'gives the upload\u2019s loadstart the size of the body', () => {
			// WebKit drops a `Blob` sent to a `data:` URL, so an empty body
			// stands in for it.
			class StartingXMLHttpRequest extends FakeXMLHttpRequest {
				send( ...args ) {
					super.send( ...args );
					this.upload.dispatchEvent(
						new ProgressEvent( 'loadstart', {
							loaded: 0,
							total: 0,
						} )
					);
				}
			}
			const Relay = createRelayXMLHttpRequest( StartingXMLHttpRequest, {
				restRelay: REST_RELAY,
			} );
			const xhr = new Relay();
			const starts = [];
			xhr.upload.addEventListener( 'loadstart', ( event ) =>
				starts.push( [
					event.loaded,
					event.total,
					event.lengthComputable,
				] )
			);
			xhr.open( 'POST', 'https://example.org/upload' );
			xhr.send( new NodeBlob( [ 'eleven byte' ] ) );
			xhr.abort();

			expect( starts ).toEqual( [ [ 0, 11, true ] ] );
		} );

		it( 'sends a FormData body to the stand-in, for its size', () => {
			const form = new FormData();
			form.append( 'title', 'Hello' );
			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'POST', 'https://example.org/upload' );
			xhr.send( form );
			xhr.abort();

			expect( xhr.callsTo( 'send' ) ).toEqual( [ [ form ] ] );
		} );

		it( 'never sends the body when the request is opened again', async () => {
			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'POST', 'https://example.org/upload' );
			xhr.send( new NodeBlob( [ 'x' ] ) );
			xhr.open( 'GET', 'https://example.org/b' );
			await settle();

			expect( xhr.callsTo( 'send' ) ).toEqual( [] );
		} );

		it( 'ends a request whose body could not be read with a network error', async () => {
			const unreadable = new NodeBlob( [ 'x' ] );
			vi.stubGlobal(
				'Response',
				class {
					headers = new Headers();
					arrayBuffer() {
						return Promise.reject( new Error( 'file is gone' ) );
					}
				}
			);

			const xhr = new RelayXMLHttpRequest();
			try {
				xhr.open( 'POST', 'https://example.org/upload' );
				xhr.send( unreadable );
				await settle();
			} finally {
				vi.unstubAllGlobals();
			}

			expect( xhr.calls.slice( -2 ) ).toEqual( [
				[ 'open', 'POST', 'data:;base64,%' ],
				[ 'send', '' ],
			] );
		} );
	} );

	describe( 'state errors', () => {
		it( 'refuses a second send while the body is read', () => {
			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'POST', 'https://example.org/upload' );
			xhr.send( new NodeBlob( [ 'x' ] ) );

			expect( () => xhr.send( 'again' ) ).toThrow(
				expect.objectContaining( { name: 'InvalidStateError' } )
			);
			expect( () => {
				xhr.withCredentials = true;
			} ).toThrow(
				expect.objectContaining( { name: 'InvalidStateError' } )
			);
			expect( () => xhr.setRequestHeader( 'X-Late', '1' ) ).toThrow(
				expect.objectContaining( { name: 'InvalidStateError' } )
			);
			expect( xhr.callsTo( 'setRequestHeader' ) ).toEqual( [] );
		} );

		it( 'lets a listener the browser calls during send open the request again', () => {
			// A synchronous request fires its `load` before `send()` returns.
			class LoadingXMLHttpRequest extends FakeXMLHttpRequest {
				send( ...args ) {
					super.send( ...args );
					this.dispatchEvent( new Event( 'load' ) );
				}
			}
			const Relay = createRelayXMLHttpRequest( LoadingXMLHttpRequest, {
				restRelay: REST_RELAY,
			} );
			const xhr = new Relay();
			xhr.addEventListener(
				'load',
				() => xhr.open( 'GET', 'https://example.org/b', false ),
				{ once: true }
			);
			xhr.open( 'GET', 'https://example.org/a', false );
			xhr.send();

			expect( () => xhr.send() ).not.toThrow();
			expect( xhr.callsTo( 'send' ) ).toHaveLength( 2 );
		} );

		it( 'passes a header set after send to the browser to refuse', () => {
			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'POST', 'https://example.org/upload' );
			xhr.send( 'x' );
			xhr.setRequestHeader( 'Content-Type', 'text/plain' );

			expect( xhr.callsTo( 'setRequestHeader' ) ).toEqual( [
				[ 'Content-Type', 'text/plain' ],
			] );
		} );

		it( 'throws for a malformed Content-Type when it is set', () => {
			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'POST', 'https://example.org/upload' );

			expect( () =>
				xhr.setRequestHeader( 'Content-Type', 'a\nb' )
			).toThrow();
		} );
	} );

	describe( 'requests it leaves alone', () => {
		/**
		 * Asserts `open()` reached the browser unchanged.
		 *
		 * @param {...unknown} args The `open()` arguments.
		 */
		function expectPassthrough( ...args ) {
			const xhr = new RelayXMLHttpRequest();
			xhr.open( ...args );
			expect( xhr.callsTo( 'open' ) ).toEqual( [ args ] );
		}

		it( 'a request to native code itself', () => {
			expectPassthrough( 'POST', 'gbk-upload://upload/sessions' );
			expectPassthrough( 'GET', relayed( 'https://example.org/a' ) );
		} );

		it( 'a blob or data read', () => {
			expectPassthrough( 'GET', 'blob:https://example.com/abc-123' );
			expectPassthrough( 'GET', 'data:text/plain,hello' );
		} );

		it( "a request to the page's own origin", () => {
			expectPassthrough(
				'GET',
				`${ window.location.origin }/src/translations.json`
			);
		} );

		it( 'a URL or open() call with a user name or password', () => {
			expectPassthrough( 'GET', 'https://user:pass@example.org/api' );
			expectPassthrough( 'GET', 'https://example.org/api', true, 'u' );
			expectPassthrough(
				'GET',
				'https://example.org/api',
				true,
				null,
				'p'
			);
		} );

		it( 'and sends its body as it is', () => {
			const body = new NodeBlob( [ 'x' ] );
			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'POST', 'gbk-upload://upload/sessions' );
			xhr.setRequestHeader( 'Content-Type', 'application/json' );
			xhr.send( body );

			expect( xhr.callsTo( 'setRequestHeader' ) ).toEqual( [
				[ 'Content-Type', 'application/json' ],
			] );
			expect( xhr.callsTo( 'send' ) ).toEqual( [ [ body ] ] );
		} );
	} );
} );

describe( 'installXMLHttpRequestRelay', () => {
	const original = window.XMLHttpRequest;

	afterEach( () => {
		window.XMLHttpRequest = original;
	} );

	beforeEach( () => {
		getGBKit.mockReset();
	} );

	it( 'does nothing when no relay is advertised', () => {
		getGBKit.mockReturnValue( {} );
		installXMLHttpRequestRelay();

		expect( window.XMLHttpRequest ).toBe( original );
	} );

	it( 'installs once', () => {
		getGBKit.mockReturnValue( { restRelay: REST_RELAY } );
		installXMLHttpRequestRelay();
		const installed = window.XMLHttpRequest;
		installXMLHttpRequestRelay();

		expect( installed ).not.toBe( original );
		expect( window.XMLHttpRequest ).toBe( installed );
		expect( Object.getPrototypeOf( installed ) ).toBe( original );
	} );
} );
