import { Blob as NodeBlob } from 'node:buffer';
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
	createRelayXMLHttpRequest,
	installXMLHttpRequestRelay,
	reportUploadProgress,
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
	 * The headers set, apart from the upload's name, which only the upload
	 * progress tests look at.
	 *
	 * @return {Array} Each header's name and value.
	 */
	headersSet() {
		return this.callsTo( 'setRequestHeader' ).filter(
			( [ name ] ) => name !== 'X-GBK-Relay-Upload'
		);
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

			expect( xhr.headersSet() ).toEqual( [
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
			expect( xhr.headersSet() ).toEqual( [
				[ 'Content-Type', 'application/offset+octet-stream' ],
			] );
		} );

		it( 'gives a Blob without a Content-Type its own type', async () => {
			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'POST', 'https://example.org/upload' );
			xhr.send( new NodeBlob( [ '{}' ], { type: 'application/json' } ) );
			await settle();

			expect( xhr.headersSet() ).toEqual( [
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
			expect( xhr.headersSet() ).toEqual( [
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

		it( 'sends a synchronous request’s Blob as it is, since it cannot wait', () => {
			const body = new NodeBlob( [ 'x' ] );
			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'POST', 'https://example.org/upload', false );
			xhr.send( body );

			expect( xhr.callsTo( 'send' ) ).toEqual( [ [ body ] ] );
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

			expect( xhr.headersSet() ).toEqual( [
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

			expect( xhr.headersSet() ).toContainEqual( [
				'X-GBK-Relay-Timeout',
				'300',
			] );
		} );

		it( 'sends no timeout when there is none', () => {
			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'GET', 'https://example.org/a' );
			xhr.send();

			expect( xhr.headersSet() ).toEqual( [] );
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

	describe( 'upload progress from native code', () => {
		/**
		 * The upload `progress` events a request fires, with their sizes.
		 *
		 * @param {XMLHttpRequest} xhr The request.
		 * @return {Array} Each event's `loaded` and `total`.
		 */
		function recordProgress( xhr ) {
			const events = [];
			xhr.upload.addEventListener( 'progress', ( event ) =>
				events.push( [
					event.loaded,
					event.total,
					event.lengthComputable,
				] )
			);
			return events;
		}

		/**
		 * The name the request gave its upload, from the header it sent.
		 *
		 * @param {XMLHttpRequest} xhr The request.
		 * @return {string|undefined} The upload's name.
		 */
		function uploadID( xhr ) {
			return xhr
				.callsTo( 'setRequestHeader' )
				.find( ( [ name ] ) => name === 'X-GBK-Relay-Upload' )?.[ 1 ];
		}

		it( 'names each relayed upload in a header', () => {
			const first = new RelayXMLHttpRequest();
			recordProgress( first );
			first.open( 'POST', 'https://example.org/upload' );
			first.send( 'one' );
			const second = new RelayXMLHttpRequest();
			recordProgress( second );
			second.open( 'POST', 'https://example.org/upload' );
			second.send( 'two' );

			expect( uploadID( first ) ).toEqual( expect.any( String ) );
			expect( uploadID( second ) ).toEqual( expect.any( String ) );
			expect( uploadID( first ) ).not.toBe( uploadID( second ) );
		} );

		it( 'names no upload for a request without a body, or one not relayed', () => {
			const get = new RelayXMLHttpRequest();
			recordProgress( get );
			get.open( 'GET', 'https://example.org/a' );
			get.send();
			const notRelayed = new RelayXMLHttpRequest();
			recordProgress( notRelayed );
			notRelayed.open( 'POST', 'gbk-upload://upload/sessions' );
			notRelayed.send( '{}' );

			expect( uploadID( get ) ).toBeUndefined();
			expect( uploadID( notRelayed ) ).toBeUndefined();
		} );

		it( 'fires progress for each report, before the upload finishes', () => {
			const xhr = new RelayXMLHttpRequest();
			const events = recordProgress( xhr );
			xhr.open( 'POST', 'https://example.org/upload' );
			xhr.send( 'x'.repeat( 100 ) );
			const id = uploadID( xhr );

			reportUploadProgress( id, 25, 100 );
			reportUploadProgress( id, 60, 100 );
			xhr.receiveHeaders();

			expect( events ).toEqual( [
				[ 25, 100, true ],
				[ 60, 100, true ],
				[ 100, 100, true ],
			] );
		} );

		it( 'finishes the upload when the whole body is sent, before the response', () => {
			// As the browser does for a request it sends itself.
			const xhr = new RelayXMLHttpRequest();
			const events = [];
			for ( const type of [ 'progress', 'load', 'loadend' ] ) {
				xhr.upload.addEventListener( type, ( event ) =>
					events.push( [ type, event.loaded, xhr.readyState ] )
				);
			}
			xhr.open( 'POST', 'https://example.org/upload' );
			xhr.send( 'x'.repeat( 100 ) );
			const id = uploadID( xhr );

			reportUploadProgress( id, 60, 100 );
			reportUploadProgress( id, 100, 100 );
			xhr.receiveHeaders();
			reportUploadProgress( id, 100, 100 );

			expect( events ).toEqual( [
				[ 'progress', 60, 1 ],
				[ 'progress', 100, 1 ],
				[ 'load', 100, 1 ],
				[ 'loadend', 100, 1 ],
			] );
		} );

		it( 'passes on the upload events of a request that failed while sending', () => {
			const xhr = new RelayXMLHttpRequest();
			const events = [];
			for ( const type of [ 'abort', 'loadend' ] ) {
				xhr.upload.addEventListener( type, () => events.push( type ) );
			}
			xhr.open( 'POST', 'https://example.org/upload' );
			xhr.send( 'x'.repeat( 100 ) );
			reportUploadProgress( uploadID( xhr ), 60, 100 );
			xhr.upload.dispatchEvent( new ProgressEvent( 'abort' ) );
			xhr.upload.dispatchEvent( new ProgressEvent( 'loadend' ) );

			expect( events ).toEqual( [ 'abort', 'loadend' ] );
		} );

		it( 'fires no upload events unless the caller read upload before send', () => {
			// The browser fires none for a listener added after `send()`.
			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'POST', 'https://example.org/upload' );
			xhr.send( 'x'.repeat( 100 ) );
			const events = recordProgress( xhr );
			xhr.receiveHeaders();

			expect( uploadID( xhr ) ).toBeUndefined();
			expect( events ).toEqual( [] );
		} );

		it( 'fires no upload events for a listener added before an abort during the read', () => {
			// The stand-in request that ends it would otherwise fire them.
			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'PATCH', 'https://example.org/files/abc' );
			xhr.send( new NodeBlob( [ 'chunk bytes' ] ) );
			const events = [];
			for ( const type of [ 'loadstart', 'abort', 'loadend' ] ) {
				xhr.upload.addEventListener( type, () => events.push( type ) );
			}
			xhr.abort();
			for ( const type of [ 'loadstart', 'abort', 'loadend' ] ) {
				xhr.upload.dispatchEvent( new ProgressEvent( type ) );
			}

			expect( events ).toEqual( [] );
		} );

		it( 'fires the upload events of an abort during the read to a listener added before send', () => {
			const xhr = new RelayXMLHttpRequest();
			const events = [];
			for ( const type of [ 'abort', 'loadend' ] ) {
				xhr.upload.addEventListener( type, () => events.push( type ) );
			}
			xhr.open( 'PATCH', 'https://example.org/files/abc' );
			xhr.send( new NodeBlob( [ 'chunk bytes' ] ) );
			xhr.abort();
			for ( const type of [ 'abort', 'loadend' ] ) {
				xhr.upload.dispatchEvent( new ProgressEvent( type ) );
			}

			expect( events ).toEqual( [ 'abort', 'loadend' ] );
		} );

		it( 'fires no upload events for a listener added while the body is read', async () => {
			const xhr = new RelayXMLHttpRequest();
			xhr.open( 'PATCH', 'https://example.org/files/abc' );
			xhr.send( new NodeBlob( [ 'chunk bytes' ] ) );
			const events = recordProgress( xhr );
			await settle();
			xhr.receiveHeaders();

			expect( uploadID( xhr ) ).toBeUndefined();
			expect( events ).toEqual( [] );
		} );

		it( 'gives a body read before sending a name, once it is sent', async () => {
			const xhr = new RelayXMLHttpRequest();
			const events = recordProgress( xhr );
			xhr.open( 'PATCH', 'https://example.org/files/abc' );
			xhr.send( new NodeBlob( [ 'chunk bytes' ] ) );
			await settle();

			reportUploadProgress( uploadID( xhr ), 4, 11 );

			expect( events ).toEqual( [ [ 4, 11, true ] ] );
		} );

		it( 'drops a report that arrives out of order', () => {
			// Native code reports from several threads, so reports can arrive
			// out of order.
			const xhr = new RelayXMLHttpRequest();
			const events = recordProgress( xhr );
			xhr.open( 'POST', 'https://example.org/upload' );
			xhr.send( 'x'.repeat( 100 ) );
			const id = uploadID( xhr );

			reportUploadProgress( id, 60, 100 );
			reportUploadProgress( id, 25, 100 );
			reportUploadProgress( id, 60, 100 );

			expect( events ).toEqual( [ [ 60, 100, true ] ] );
		} );

		it( 'drops a report that arrives after the response', () => {
			const xhr = new RelayXMLHttpRequest();
			const events = recordProgress( xhr );
			xhr.open( 'POST', 'https://example.org/upload' );
			xhr.send( 'x'.repeat( 100 ) );
			const id = uploadID( xhr );
			xhr.receiveHeaders();

			reportUploadProgress( id, 60, 100 );

			expect( events ).toEqual( [ [ 100, 100, true ] ] );
		} );

		it( 'drops a report for a request that ended, or was opened again', () => {
			const ended = new RelayXMLHttpRequest();
			const endedEvents = recordProgress( ended );
			ended.open( 'POST', 'https://example.org/upload' );
			ended.send( 'x'.repeat( 100 ) );
			ended.dispatchEvent( new Event( 'loadend' ) );
			reportUploadProgress( uploadID( ended ), 60, 100 );

			const reopened = new RelayXMLHttpRequest();
			const reopenedEvents = recordProgress( reopened );
			reopened.open( 'POST', 'https://example.org/upload' );
			reopened.send( 'x'.repeat( 100 ) );
			const id = uploadID( reopened );
			reopened.open( 'POST', 'https://example.org/upload' );
			reportUploadProgress( id, 60, 100 );

			expect( endedEvents ).toEqual( [] );
			expect( reopenedEvents ).toEqual( [] );
		} );

		it( 'ignores a report for an upload it doesn’t know', () => {
			expect( () =>
				reportUploadProgress( 'unknown', 1, 2 )
			).not.toThrow();
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

			expect( xhr.headersSet() ).toEqual( [
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

			expect( xhr.headersSet() ).toEqual( [
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

	it( 'gives native code a function to report upload progress', () => {
		getGBKit.mockReturnValue( { restRelay: REST_RELAY } );
		installXMLHttpRequestRelay();

		expect( window.editor.relayUploadProgress ).toBe(
			reportUploadProgress
		);
	} );

	it( 'adds nothing to XMLHttpRequest that the browser’s lacks', () => {
		getGBKit.mockReturnValue( { restRelay: REST_RELAY } );
		installXMLHttpRequestRelay();

		expect( Object.getOwnPropertyNames( window.XMLHttpRequest ) ).toEqual(
			expect.not.arrayContaining( [ 'reportUploadProgress' ] )
		);
	} );
} );
