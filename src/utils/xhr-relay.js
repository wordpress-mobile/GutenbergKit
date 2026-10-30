import { getGBKit } from './bridge';
import { debug, warn } from './logger';
import { bufferedBody, isRelayed, relayURL } from './fetch-relay';

/**
 * Marks the relaying `XMLHttpRequest` as ours. Registered globally so a second
 * copy of this module — a re-injected bundle — recognizes it rather than
 * relaying through two layers.
 */
const INSTALLED = Symbol.for( 'gutenbergkit.xhrRelay' );

/** `XMLHttpRequest.UNSENT`. */
const UNSENT = 0;

/** `XMLHttpRequest.OPENED`. */
const OPENED = 1;

/** `XMLHttpRequest.HEADERS_RECEIVED`. */
const HEADERS_RECEIVED = 2;

/**
 * The request header that tells native code the request's `timeout`, in
 * milliseconds. `RestRelaySchemeHandler.timeoutHeader` in native code.
 */
const TIMEOUT_HEADER = 'X-GBK-Relay-Timeout';

/** The events the relay fires itself, in place of or as well as WebKit's. */
const OWN_EVENTS = new WeakSet();

/**
 * A `data:` URL that fails to decode. A request for it fails as a network
 * error, without leaving the web view.
 */
const FAILING_URL = 'data:;base64,%';

/**
 * Replaces the global `XMLHttpRequest` with one that sends requests to other
 * origins through the native relay, as `createRelayFetch` does for `fetch`.
 *
 * Does nothing when the host is not running a relay, or when this is already
 * installed.
 *
 * @return {void}
 */
export function installXMLHttpRequestRelay() {
	const { restRelay } = getGBKit();

	if ( ! restRelay ) {
		return;
	}

	if ( window.XMLHttpRequest[ INSTALLED ] ) {
		debug( 'The XMLHttpRequest relay is already installed' );
		return;
	}

	const RelayXMLHttpRequest = createRelayXMLHttpRequest(
		window.XMLHttpRequest,
		{ restRelay }
	);
	RelayXMLHttpRequest[ INSTALLED ] = true;
	window.XMLHttpRequest = RelayXMLHttpRequest;
	debug( `Relaying XMLHttpRequests through ${ restRelay.endpoint }` );
}

/**
 * A subclass of `XMLHttpRequest` that sends requests to other origins through
 * the native relay.
 *
 * Plugins and the libraries they bundle — jQuery's `$.ajax`, `tus-js-client`,
 * axios in a browser — send their requests with `XMLHttpRequest`, not `fetch`.
 * Under iOS Lockdown Mode those fail CORS just as `fetch` does, so they take
 * the same relay. Which requests it takes is the same too: see `isRelayed`.
 *
 * Only the URL changes. The browser's own `XMLHttpRequest` still sends the
 * request, so events, `responseType` and synchronous requests behave as they
 * would without the relay. What this adds to keep it that way:
 *
 * - `responseURL` is the URL the caller opened, not the relay's. A redirect
 *   native code followed doesn't show in it.
 * - `withCredentials` reads back as the caller set it, but the request is sent
 *   without cookies. The relay answers `Access-Control-Allow-Origin: *`, which
 *   a browser refuses to pair with a credentialed request.
 * - A `Blob` or `FormData` body is read into an `ArrayBuffer` before it is sent,
 *   because WebKit drops those bodies on the way to native code (see
 *   `bufferedBody`). Its `loadstart` events still fire at `send()`, as the
 *   browser's do, and the browser's own are stopped once the body is read and
 *   sent. A synchronous request can't wait for the read, so its body is read
 *   synchronously instead (see `readSynchronously`). An `abort()` during the
 *   read ends the request with the events an abort fires.
 * - WebKit doesn't apply `timeout` to a request native code answers, so native
 *   code enforces it. It is read when the request is sent, so a change to it
 *   after `send()` has no effect.
 * - WebKit fires no upload `progress`, `load` or `loadend` for a request native
 *   code answers. They are fired once the response's headers arrive, by which
 *   time native code has sent the whole body. An upload's progress jumps from
 *   nothing to done. WebKit still counts the upload as unfinished, so an abort,
 *   timeout or error after that would fire upload events a second time. Those
 *   are stopped before the caller's listeners hear them. As in the browser, an
 *   empty body gets none.
 * - The response has no `Content-Length`, because native code drops it. So
 *   download `progress` events have `lengthComputable` false and a `total` of 0.
 *
 * @param {typeof XMLHttpRequest}        Base             The class to extend.
 * @param {Object}                       config           Relay configuration.
 * @param {import('./bridge').RestRelay} config.restRelay Where the relay is.
 * @return {typeof XMLHttpRequest} The relaying class.
 */
export function createRelayXMLHttpRequest( Base, { restRelay } ) {
	return class XMLHttpRequest extends Base {
		/** The URL the caller opened, when the request is relayed. */
		#target = null;

		#method = 'GET';

		#async = true;

		/** The caller's `Content-Type` values, held back until `send()`. */
		#contentTypes = [];

		#withCredentials = false;

		/** Whether `send()` was called since `open()`. */
		#sent = false;

		/** Identifies a `send()` that is waiting for its body to be read. */
		#pending = null;

		/**
		 * The size of the body being uploaded, `null` when its size isn't
		 * known, or `undefined` when no upload events are owed.
		 */
		#uploadSize = undefined;

		/** Whether this fired the upload's `load` for the current request. */
		#uploadComplete = false;

		/** Whether the upload object has the listener that stops WebKit's late events. */
		#uploadGuarded = false;

		/** Counts the calls to `open()` and `abort()`, which each end a request. */
		#ended = 0;

		/**
		 * Whether the caller ended the request from an upload listener, where
		 * the browser would never have received its response.
		 */
		#responseHidden = false;

		/**
		 * Whether the relay fired the `loadstart` events at `send()`, so the
		 * browser's own are stopped when it sends the request.
		 */
		#startFired = false;

		constructor() {
			super();
			// Added first, so the upload events go out before the caller's own
			// listeners hear that the headers arrived, as they would without
			// the relay.
			this.addEventListener( 'readystatechange', ( event ) => {
				if (
					this.readyState !== HEADERS_RECEIVED ||
					this.#uploadSize === undefined
				) {
					return;
				}
				const ended = this.#ended;
				this.#completeUpload();
				if ( this.#ended !== ended ) {
					this.#forgetResponse( event );
				}
			} );
			// Added first, so the caller's listeners never hear it.
			this.addEventListener( 'loadstart', ( event ) => {
				if ( this.#startFired && ! OWN_EVENTS.has( event ) ) {
					event.stopImmediatePropagation();
				}
			} );
		}

		open( method, url, ...rest ) {
			const target = relayedTarget( url, rest );

			super.open(
				method,
				target ? relayURL( restRelay, target ) : url,
				...rest
			);

			this.#target = target;
			this.#method = String( method ).toUpperCase();
			// WebIDL makes an `async` argument of `undefined` false. Only an
			// omitted one is true.
			this.#async = rest.length === 0 || Boolean( rest[ 0 ] );
			this.#contentTypes = [];
			this.#sent = false;
			this.#pending = null;
			this.#uploadSize = undefined;
			this.#uploadComplete = false;
			this.#responseHidden = false;
			this.#startFired = false;
			this.#ended++;
			super.withCredentials = target ? false : this.#withCredentials;
		}

		get withCredentials() {
			return this.#withCredentials;
		}

		set withCredentials( value ) {
			// The browser refuses it once the request is sent, but doesn't
			// know a request waiting for its body has been.
			if ( this.#pending ) {
				throw invalidState( 'withCredentials' );
			}
			super.withCredentials = this.#target ? false : value;
			this.#withCredentials = Boolean( value );
		}

		setRequestHeader( name, value ) {
			// The browser refuses it once the request is sent, but doesn't
			// know a request waiting for its body has been.
			if ( this.#pending ) {
				throw invalidState( 'setRequestHeader' );
			}
			// A relayed `FormData` body gets a new boundary when it is read, so
			// its `Content-Type` is only known at `send()`.
			if (
				this.#target &&
				! this.#sent &&
				this.readyState === OPENED &&
				String( name ).toLowerCase() === 'content-type'
			) {
				// Throws for a malformed value, as `setRequestHeader` would.
				new Headers().append( name, value );
				this.#contentTypes.push( value );
				return;
			}
			super.setRequestHeader( name, value );
		}

		send( body ) {
			if ( this.#target && this.#sent ) {
				throw invalidState( 'send' );
			}

			if ( ! this.#target || this.readyState !== OPENED ) {
				return super.send( body );
			}

			const sent =
				this.#method === 'GET' || this.#method === 'HEAD' ? null : body;

			// Set before the browser's `send()`, which can fire events whose
			// listeners open the request again.
			this.#sent = true;

			if ( ! this.#async ) {
				if ( ! isReadBeforeSending( sent ) ) {
					for ( const type of this.#contentTypes ) {
						super.setRequestHeader( 'Content-Type', type );
					}
					super.send( sent );
					return;
				}
				const headers = new Headers();
				for ( const type of this.#contentTypes ) {
					headers.append( 'Content-Type', type );
				}
				const read = readSynchronously( sent, headers, Base );
				const type = headers.get( 'Content-Type' );
				if ( type !== null ) {
					super.setRequestHeader( 'Content-Type', type );
				}
				super.send( read );
				return;
			}

			const startedAt = Date.now();
			if ( ! isReadBeforeSending( sent ) ) {
				for ( const type of this.#contentTypes ) {
					super.setRequestHeader( 'Content-Type', type );
				}
				this.#sendRelayed( sent, startedAt );
				return;
			}

			const pending = { body: sent };
			this.#pending = pending;
			if ( ! this.#fireLoadStart( sent, pending ) ) {
				return;
			}
			const headers = new Headers();
			for ( const type of this.#contentTypes ) {
				headers.append( 'Content-Type', type );
			}

			bufferedBody( sent, headers ).then(
				( buffered ) => {
					// Aborted, or opened again, while the body was read.
					if ( this.#pending !== pending ) {
						return;
					}
					this.#pending = null;
					const type = headers.get( 'Content-Type' );
					if ( type !== null ) {
						super.setRequestHeader( 'Content-Type', type );
					}
					this.#sendRelayed( buffered, startedAt );
				},
				( err ) => {
					if ( this.#pending !== pending ) {
						return;
					}
					this.#pending = null;
					warn( `Could not read a request body: ${ err?.message }` );
					this.#endWithoutSending( FAILING_URL, sent );
				}
			);
		}

		abort() {
			this.#ended++;
			if ( this.#pending ) {
				const { body } = this.#pending;
				this.#pending = null;
				this.#endWithoutSending( 'data:,', body );
				super.abort();
				return;
			}
			super.abort();
		}

		get upload() {
			const upload = super.upload;
			// Added the first time the caller can reach the upload object, so
			// it runs before any listener the caller adds.
			if ( ! this.#uploadGuarded ) {
				this.#uploadGuarded = true;
				for ( const type of [
					'abort',
					'error',
					'timeout',
					'loadend',
				] ) {
					upload.addEventListener( type, ( event ) => {
						if (
							this.#uploadComplete &&
							! OWN_EVENTS.has( event )
						) {
							event.stopImmediatePropagation();
						}
					} );
				}
				upload.addEventListener( 'loadstart', ( event ) => {
					if ( this.#startFired && ! OWN_EVENTS.has( event ) ) {
						event.stopImmediatePropagation();
					}
				} );
			}
			return upload;
		}

		get responseURL() {
			if ( this.#responseHidden ) {
				return '';
			}
			const url = super.responseURL;
			if ( ! this.#target || ! url ) {
				return url;
			}
			const target = new URL( this.#target );
			target.hash = '';
			return target.href;
		}

		get responseText() {
			return this.#responseHidden && this.#isText()
				? ''
				: super.responseText;
		}

		get response() {
			return this.#responseHidden && this.#isText() ? '' : super.response;
		}

		/**
		 * Fires the `loadstart` events the browser fires at `send()`, for a
		 * request that waits for its body to be read first.
		 *
		 * The upload's goes out only when the caller has reached the upload
		 * object. Without that, it can have no listeners to hear it.
		 *
		 * @param {Blob|FormData} body    The caller's body.
		 * @param {Object}        pending The `send()` waiting for the body.
		 * @return {boolean} Whether the request is still waiting to be sent: a
		 *                   listener can end it or open it again.
		 */
		#fireLoadStart( body, pending ) {
			this.#startFired = true;
			this.dispatchEvent( ownProgressEvent( 'loadstart', 0, 0 ) );
			if ( this.#pending !== pending ) {
				return false;
			}
			if ( this.#uploadGuarded ) {
				// Every boundary WebKit makes is the same length, so this
				// one gives the size WebKit's would.
				const size = isBlob( body )
					? body.size
					: multipartBody( body, formBoundary() ).size;
				super.upload.dispatchEvent(
					ownProgressEvent( 'loadstart', 0, size )
				);
			}
			return this.#pending === pending;
		}

		/**
		 * Sends a relayed asynchronous request, with what native code needs to
		 * stand in for the browser.
		 *
		 * @param {unknown} body      The body, in a form WebKit delivers.
		 * @param {number}  startedAt When `send()` was called, in milliseconds.
		 */
		#sendRelayed( body, startedAt ) {
			// Counted from `send()`, as the browser counts it.
			if ( this.timeout > 0 ) {
				const remaining = this.timeout - ( Date.now() - startedAt );
				super.setRequestHeader(
					TIMEOUT_HEADER,
					String( Math.max( remaining, 1 ) )
				);
			}
			const size =
				body === null || body === undefined ? 0 : byteSize( body );
			// The browser fires no upload `progress`, `load` or `loadend` for an
			// empty body.
			this.#uploadSize = size === 0 ? undefined : size;
			try {
				super.send( body );
			} finally {
				this.#startFired = false;
			}
		}

		/**
		 * Fires the upload events WebKit leaves out: a final `progress`, then
		 * `load` and `loadend`, in the browser's order.
		 *
		 * A `progress` listener that ends the request gets the upload's `abort`
		 * from WebKit instead of `load`. After `progress`, the upload is
		 * complete, so ending the request fires no more upload events.
		 */
		#completeUpload() {
			const size = this.#uploadSize;
			this.#uploadSize = undefined;
			const ended = this.#ended;
			const event = ( type ) =>
				ownProgressEvent( type, size ?? 0, size ?? 0 );

			this.upload.dispatchEvent( event( 'progress' ) );
			if ( this.#ended !== ended ) {
				return;
			}
			this.#uploadComplete = true;
			this.upload.dispatchEvent( event( 'load' ) );
			this.upload.dispatchEvent( event( 'loadend' ) );
		}

		/**
		 * Hides a response the caller ended the request before, from an upload
		 * listener.
		 *
		 * The browser fires the upload's events before the response arrives, so
		 * a caller that ends the request there never hears of the response.
		 * Here they fire as its headers arrive, so this keeps the caller's own
		 * listeners from hearing that they did.
		 *
		 * WebKit also keeps the response's URL after an `abort()`, and the text
		 * that was arriving as it was called here, so those read as empty until
		 * the request is opened again. Its other getters already give nothing
		 * once a request is aborted.
		 *
		 * @param {Event} event The `readystatechange` for the headers.
		 */
		#forgetResponse( event ) {
			event.stopImmediatePropagation();
			this.#responseHidden = this.readyState === UNSENT;
		}

		/**
		 * Whether the response is read as text, the only form WebKit keeps
		 * after an `abort()`.
		 *
		 * @return {boolean} Whether it is.
		 */
		#isText() {
			return this.responseType === '' || this.responseType === 'text';
		}

		/**
		 * Ends a request whose body was never sent, with the events the browser
		 * fires for one that was.
		 *
		 * Only the browser can move an `XMLHttpRequest` through its states and
		 * fire its events, and only for a request it sent. So the request is
		 * opened again for a `data:` URL, which never leaves the web view, and
		 * sent with the caller's body, so its upload events give the body's
		 * size. The caller aborts it straight away, or lets an undecodable URL
		 * fail.
		 *
		 * WebKit drops a `Blob` sent to a `data:` URL, so an empty body goes in
		 * its place. The `loadstart` events already fired at `send()`, with the
		 * body's size, so the ones this request fires are stopped.
		 *
		 * @param {string}  url  The `data:` URL to send it to.
		 * @param {unknown} body The caller's body.
		 */
		#endWithoutSending( url, body ) {
			super.open( 'POST', url );
			try {
				super.send( isBlob( body ) ? '' : body );
			} finally {
				this.#startFired = false;
			}
		}
	};
}

/**
 * The URL an `open()` call addresses when it is relayed, or `null` when it
 * isn't.
 *
 * An `open()` with a user name or password is left alone, as a URL with them
 * is: the relay has no way to send them.
 *
 * @param {string|URL} url  The URL passed to `open()`.
 * @param {Array}      rest The arguments after it.
 * @return {URL|null} The target URL.
 */
function relayedTarget( url, rest ) {
	const [ , username, password ] = rest;
	if (
		( username !== undefined && username !== null ) ||
		( password !== undefined && password !== null )
	) {
		return null;
	}

	let target;
	try {
		target = new URL( url, document.baseURI );
	} catch {
		// `open()` throws for it.
		return null;
	}
	return isRelayed( target ) ? target : null;
}

/**
 * Whether a body has to be read before it is sent: a `Blob`, `File`, or
 * `FormData`, which WebKit drops on the way to native code.
 *
 * Checked by type tag rather than `instanceof`, so one made in another window
 * is recognized too.
 *
 * @param {unknown} body The request body.
 * @return {boolean} Whether to read it first.
 */
function isReadBeforeSending( body ) {
	return (
		isBlob( body ) ||
		Object.prototype.toString.call( body ) === '[object FormData]'
	);
}

/**
 * Whether a body is a `Blob` or `File`, from any window.
 *
 * @param {unknown} body The request body.
 * @return {boolean} Whether it is a `Blob`.
 */
function isBlob( body ) {
	return [ '[object Blob]', '[object File]' ].includes(
		Object.prototype.toString.call( body )
	);
}

/**
 * A `Blob`, `File`, or `FormData` body read into an `ArrayBuffer` without
 * waiting, for a synchronous request. Names the body's type as `bufferedBody`
 * does.
 *
 * The page has no synchronous way to read a `Blob` (`FileReaderSync` exists only
 * in workers), but a synchronous `XMLHttpRequest` for a `blob:` URL reads it.
 * Decoded as `x-user-defined`, each byte becomes one character: an ASCII byte
 * as itself, and the rest as U+F780 to U+F7FF.
 *
 * @param {Blob|FormData}         body    The request body.
 * @param {Headers}               headers The request headers, updated in place.
 * @param {typeof XMLHttpRequest} Base    The browser's `XMLHttpRequest`.
 * @return {ArrayBuffer} The body's bytes.
 * @throws {DOMException} A `NetworkError`, as a failed synchronous request does,
 *                        when the body can't be read.
 */
function readSynchronously( body, headers, Base ) {
	let blob = body;
	if ( Object.prototype.toString.call( body ) === '[object FormData]' ) {
		const boundary = formBoundary();
		blob = multipartBody( body, boundary );
		headers.set(
			'Content-Type',
			`multipart/form-data; boundary=${ boundary }`
		);
	} else if ( blob.type && ! headers.has( 'Content-Type' ) ) {
		headers.set( 'Content-Type', blob.type );
	}

	const url = URL.createObjectURL( blob );
	try {
		const reader = new Base();
		reader.open( 'GET', url, false );
		reader.overrideMimeType( 'text/plain; charset=x-user-defined' );
		reader.send();
		const text = reader.responseText;
		const bytes = new Uint8Array( text.length );
		for ( let i = 0; i < text.length; i++ ) {
			bytes[ i ] = text.charCodeAt( i ) % 256;
		}
		return bytes.buffer;
	} catch ( err ) {
		warn( `Could not read a request body: ${ err?.message }` );
		throw new DOMException(
			"Failed to execute 'send' on 'XMLHttpRequest': the body could not be read.",
			'NetworkError'
		);
	} finally {
		URL.revokeObjectURL( url );
	}
}

/**
 * A multipart boundary in the form WebKit uses.
 *
 * @return {string} The boundary.
 */
function formBoundary() {
	const characters =
		'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
	const random = crypto.getRandomValues( new Uint8Array( 16 ) );
	return `----WebKitFormBoundary${ Array.from(
		random,
		( byte ) => characters[ byte % characters.length ]
	).join( '' ) }`;
}

/**
 * A `FormData` serialized as `multipart/form-data`, as a `Blob` that holds its
 * files rather than copies of them.
 *
 * Follows the HTML standard's multipart/form-data encoding: line breaks in
 * names and string values become CRLF, and a name or file name escapes CR, LF
 * and `"`.
 *
 * @param {FormData} formData The form data.
 * @param {string}   boundary The boundary between its parts.
 * @return {Blob} The serialized form data.
 */
function multipartBody( formData, boundary ) {
	const parts = [];
	for ( const [ name, value ] of formData ) {
		parts.push(
			`--${ boundary }\r\nContent-Disposition: form-data; name="${ escapeFormName(
				normalizeLineBreaks( name )
			) }"`
		);
		if ( typeof value === 'string' ) {
			parts.push( `\r\n\r\n${ normalizeLineBreaks( value ) }\r\n` );
		} else {
			parts.push(
				`; filename="${ escapeFormName(
					value.name
				) }"\r\nContent-Type: ${
					value.type || 'application/octet-stream'
				}\r\n\r\n`,
				value,
				'\r\n'
			);
		}
	}
	parts.push( `--${ boundary }--\r\n` );
	return new Blob( parts );
}

/**
 * A string with every lone CR or LF made a CRLF.
 *
 * @param {string} value The string.
 * @return {string} The normalized string.
 */
function normalizeLineBreaks( value ) {
	return value.replace( /\r(?!\n)|(?<!\r)\n/g, '\r\n' );
}

/**
 * A form entry's name or file name, escaped for a `Content-Disposition` header.
 *
 * @param {string} value The name.
 * @return {string} The escaped name.
 */
function escapeFormName( value ) {
	return value
		.replace( /\n/g, '%0A' )
		.replace( /\r/g, '%0D' )
		.replace( /"/g, '%22' );
}

/**
 * The size in bytes a body is sent as, or `null` when it can't be told without
 * serializing it.
 *
 * @param {unknown} body A body WebKit delivers: no `Blob` or `File`.
 * @return {number|null} The size.
 */
function byteSize( body ) {
	if ( typeof body === 'string' ) {
		return new TextEncoder().encode( body ).byteLength;
	}
	// By type tag, so a buffer or parameters made in another window count too.
	const tag = Object.prototype.toString.call( body );
	if ( tag === '[object ArrayBuffer]' || ArrayBuffer.isView( body ) ) {
		return body.byteLength;
	}
	if ( tag === '[object URLSearchParams]' ) {
		return new TextEncoder().encode( String( body ) ).byteLength;
	}
	return null;
}

/**
 * A progress event the relay fires itself, which its guards let through.
 *
 * @param {string} type   The event type.
 * @param {number} loaded The bytes sent.
 * @param {number} total  The body's size, or 0 when it isn't known.
 * @return {ProgressEvent} The event.
 */
function ownProgressEvent( type, loaded, total ) {
	// As WebKit makes them: the length is computable whenever there is one.
	const event = new ProgressEvent( type, {
		lengthComputable: total > 0,
		loaded,
		total,
	} );
	OWN_EVENTS.add( event );
	return event;
}

/**
 * The error `XMLHttpRequest` throws for a call in the wrong state.
 *
 * @param {string} member The method or property that was used.
 * @return {DOMException} The error.
 */
function invalidState( member ) {
	return new DOMException(
		`Failed to use '${ member }' on 'XMLHttpRequest': the object's state must be OPENED.`,
		'InvalidStateError'
	);
}
