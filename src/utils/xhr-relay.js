import { getGBKit } from './bridge';
import { debug, warn } from './logger';
import { bufferedBody, isRelayed, relayURL } from './fetch-relay';

/**
 * Marks the relaying `XMLHttpRequest` as ours. Registered globally so a second
 * copy of this module — a re-injected bundle — recognizes it rather than
 * relaying through two layers.
 */
const INSTALLED = Symbol.for( 'gutenbergkit.xhrRelay' );

/** `XMLHttpRequest.OPENED`. */
const OPENED = 1;

/** `XMLHttpRequest.HEADERS_RECEIVED`. */
const HEADERS_RECEIVED = 2;

/**
 * The request header that tells native code the request's `timeout`, in
 * milliseconds. `RestRelaySchemeHandler.timeoutHeader` in native code.
 */
const TIMEOUT_HEADER = 'X-GBK-Relay-Timeout';

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
 *   `bufferedBody`). The request starts once the body is read, so its
 *   `loadstart` comes later than `send()`. A synchronous request can't wait for
 *   the read, so its `Blob` or `FormData` body is sent as it is. An `abort()`
 *   during the read ends the request with the events an abort fires.
 * - WebKit doesn't apply `timeout` to a request native code answers, so native
 *   code enforces it. It is read when the request is sent.
 * - WebKit fires no upload `progress`, `load` or `loadend` for a request native
 *   code answers. They are fired once the response's headers arrive, by which
 *   time native code has sent the whole body. An upload's progress jumps from
 *   nothing to done.
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

		constructor() {
			super();
			// Added first, so the upload events go out before the caller's own
			// listeners hear that the headers arrived, as they would without
			// the relay.
			this.addEventListener( 'readystatechange', () => {
				if (
					this.readyState === HEADERS_RECEIVED &&
					this.#uploadSize !== undefined
				) {
					this.#completeUpload();
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
			super.withCredentials = target ? false : this.#withCredentials;
		}

		get withCredentials() {
			return this.#withCredentials;
		}

		set withCredentials( value ) {
			if ( this.#sent ) {
				throw invalidState( 'withCredentials' );
			}
			super.withCredentials = this.#target ? false : value;
			this.#withCredentials = Boolean( value );
		}

		setRequestHeader( name, value ) {
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

			if ( ! this.#async ) {
				for ( const type of this.#contentTypes ) {
					super.setRequestHeader( 'Content-Type', type );
				}
				super.send( sent );
				this.#sent = true;
				return;
			}

			const startedAt = Date.now();
			if ( ! isReadBeforeSending( sent ) ) {
				for ( const type of this.#contentTypes ) {
					super.setRequestHeader( 'Content-Type', type );
				}
				this.#sendRelayed( sent, startedAt );
				this.#sent = true;
				return;
			}

			this.#sent = true;
			const pending = {};
			this.#pending = pending;
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
					this.#endWithoutSending( FAILING_URL );
				}
			);
		}

		abort() {
			if ( this.#pending ) {
				this.#pending = null;
				this.#endWithoutSending( 'data:,' );
				super.abort();
				return;
			}
			super.abort();
		}

		get responseURL() {
			const url = super.responseURL;
			if ( ! this.#target || ! url ) {
				return url;
			}
			const target = new URL( this.#target );
			target.hash = '';
			return target.href;
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
			this.#uploadSize =
				body === null || body === undefined
					? undefined
					: byteSize( body );
			super.send( body );
		}

		/**
		 * Fires the upload events WebKit leaves out: a final `progress`, then
		 * `load` and `loadend`.
		 */
		#completeUpload() {
			const size = this.#uploadSize;
			this.#uploadSize = undefined;
			for ( const type of [ 'progress', 'load', 'loadend' ] ) {
				this.upload.dispatchEvent(
					new ProgressEvent( type, {
						lengthComputable: size !== null,
						loaded: size ?? 0,
						total: size ?? 0,
					} )
				);
			}
		}

		/**
		 * Ends a request whose body was never sent, with the events the browser
		 * fires for one that was.
		 *
		 * Only the browser can move an `XMLHttpRequest` through its states and
		 * fire its events, and only for a request it sent. So the request is
		 * opened again for a `data:` URL, which never leaves the web view, and
		 * sent with an empty body, so its upload fires events too. The caller
		 * aborts it straight away, or lets an undecodable URL fail.
		 *
		 * @param {string} url The `data:` URL to send it to.
		 */
		#endWithoutSending( url ) {
			super.open( 'POST', url );
			super.send( '' );
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
	return [ '[object Blob]', '[object File]', '[object FormData]' ].includes(
		Object.prototype.toString.call( body )
	);
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
