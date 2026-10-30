/**
 * Runs one `XMLHttpRequest` scenario for `XMLHttpRequestRelayLifecycleTests` and
 * records what the caller sees: each event in order, the state at the end, and
 * any error a call threw.
 *
 * Expects `window.XMLHttpRequestRelay`, the relay's class, and is called with
 * `scenario`, `relayed` and `origin` (the test server's) as arguments.
 */
const Request = relayed ? window.XMLHttpRequestRelay : XMLHttpRequest;
// Nothing listens on port 1, so a request to it fails to connect.
const UNREACHABLE = 'http://127.0.0.1:1';
const TYPES = [
	'loadstart',
	'progress',
	'load',
	'error',
	'abort',
	'timeout',
	'loadend',
];

const xhr = new Request();
const events = [];
const note = ( entry ) => {
	// How many `progress` and `LOADING` updates arrive depends on timing.
	if ( events.at( -1 ) !== entry ) {
		events.push( entry );
	}
};
const attempt = ( name, call ) => {
	try {
		call();
	} catch ( error ) {
		note( `${ name } threw ${ error.name }` );
	}
};

xhr.addEventListener( 'readystatechange', () =>
	note( `readystatechange ${ xhr.readyState }` )
);
for ( const type of TYPES ) {
	xhr.addEventListener( type, () => note( type ) );
}

/**
 * Records the upload's events too. Reading `xhr.upload` changes how WebKit
 * sends the body, so only the scenarios that call this do it.
 */
function recordUpload() {
	for ( const type of TYPES ) {
		xhr.upload.addEventListener( type, ( event ) =>
			note( `upload.${ type } ${ event.loaded }/${ event.total }` )
		);
	}
}

const ended = new Promise( ( resolve ) => {
	xhr.addEventListener( 'loadend', () =>
		// Long enough for any event that would follow by mistake.
		setTimeout( resolve, 500 )
	);
} );

/** Makes the calls a sent request refuses. */
function callSentRequest() {
	attempt( 'setRequestHeader', () => xhr.setRequestHeader( 'X-Late', '1' ) );
	attempt( 'withCredentials', () => {
		xhr.withCredentials = true;
	} );
	attempt( 'send', () => xhr.send() );
}

const scenarios = {
	get() {
		xhr.open( 'GET', `${ origin }/echo` );
		xhr.send();
	},
	getJSON() {
		xhr.open( 'GET', `${ origin }/echo` );
		xhr.responseType = 'json';
		xhr.send();
	},
	postString() {
		recordUpload();
		xhr.open( 'POST', `${ origin }/echo` );
		xhr.setRequestHeader( 'Content-Type', 'text/plain' );
		xhr.send( 'a string body' );
	},
	postStringWithoutUploadListener() {
		xhr.open( 'POST', `${ origin }/echo` );
		xhr.send( 'a string body' );
	},
	postArrayBuffer() {
		recordUpload();
		xhr.open( 'PUT', `${ origin }/echo` );
		xhr.send( new Uint8Array( 300 ).fill( 7 ).buffer );
	},
	postEmptyString() {
		recordUpload();
		xhr.open( 'POST', `${ origin }/echo` );
		xhr.send( '' );
	},
	postEmptyArrayBuffer() {
		recordUpload();
		xhr.open( 'POST', `${ origin }/echo` );
		xhr.send( new ArrayBuffer( 0 ) );
	},
	postBlob() {
		recordUpload();
		xhr.open( 'PATCH', `${ origin }/echo` );
		xhr.setRequestHeader( 'Content-Type', 'application/offset+octet-stream' );
		xhr.send( new Blob( [ 'a blob body' ] ) );
	},
	postFormData() {
		recordUpload();
		const form = new FormData();
		form.append( 'title', 'Hello' );
		form.append( 'file', new Blob( [ 'file bytes' ] ), 'a.txt' );
		xhr.open( 'POST', `${ origin }/echo` );
		xhr.send( form );
	},
	abortBeforeResponse() {
		xhr.open( 'GET', `${ origin }/delay` );
		xhr.send();
		setTimeout( () => xhr.abort(), 100 );
	},
	abortAfterHeaders() {
		recordUpload();
		xhr.open( 'POST', `${ origin }/stall` );
		xhr.addEventListener( 'readystatechange', () => {
			if ( xhr.readyState === XMLHttpRequest.HEADERS_RECEIVED ) {
				setTimeout( () => xhr.abort(), 50 );
			}
		} );
		xhr.send( 'a string body' );
	},
	abortFromUploadProgress() {
		recordUpload();
		xhr.upload.addEventListener( 'progress', () => xhr.abort() );
		xhr.open( 'POST', `${ origin }/echo` );
		xhr.send( 'a string body' );
	},
	abortFromUploadLoad() {
		recordUpload();
		xhr.upload.addEventListener( 'load', () => xhr.abort() );
		xhr.open( 'POST', `${ origin }/echo` );
		xhr.send( 'a string body' );
	},
	abortWhileBlobIsRead() {
		recordUpload();
		xhr.open( 'POST', `${ origin }/echo` );
		xhr.send( new Blob( [ 'a blob body' ] ) );
		xhr.abort();
	},
	abortWhileFormDataIsRead() {
		recordUpload();
		const form = new FormData();
		form.append( 'title', 'Hello' );
		form.append( 'file', new Blob( [ 'file bytes' ] ), 'a.txt' );
		xhr.open( 'POST', `${ origin }/echo` );
		xhr.send( form );
		xhr.abort();
	},
	timeoutBeforeResponse() {
		xhr.open( 'GET', `${ origin }/delay` );
		xhr.timeout = 500;
		xhr.send();
	},
	timeoutAfterHeaders() {
		recordUpload();
		xhr.open( 'POST', `${ origin }/stall` );
		xhr.timeout = 3000;
		xhr.send( 'a string body' );
	},
	unreachable() {
		recordUpload();
		xhr.open( 'POST', `${ UNREACHABLE }/echo` );
		xhr.send( 'a string body' );
	},
	cutAfterHeaders() {
		xhr.open( 'GET', `${ origin }/cut` );
		xhr.send();
	},
	cutChunkedAfterHeaders() {
		xhr.open( 'GET', `${ origin }/cut-chunked` );
		xhr.send();
	},
	postUntypedBlob() {
		xhr.open( 'POST', `${ origin }/echo` );
		xhr.send( new Blob( [ 'a blob body' ] ) );
	},
	callsAfterSend() {
		xhr.open( 'POST', `${ origin }/echo` );
		xhr.send( 'a string body' );
		callSentRequest();
	},
	callsWhileBlobIsRead() {
		xhr.open( 'POST', `${ origin }/echo` );
		xhr.send( new Blob( [ 'a blob body' ], { type: 'text/plain' } ) );
		callSentRequest();
	},
	synchronousGet() {
		xhr.open( 'GET', `${ origin }/echo`, false );
		attempt( 'send', () => xhr.send() );
	},
	synchronousPost() {
		xhr.open( 'POST', `${ origin }/echo`, false );
		attempt( 'send', () => xhr.send( 'a string body' ) );
	},
	reopenFromSynchronousLoad() {
		let reopened = false;
		xhr.addEventListener( 'load', () => {
			if ( ! reopened ) {
				reopened = true;
				xhr.open( 'GET', `${ origin }/echo`, false );
			}
		} );
		xhr.open( 'GET', `${ origin }/echo`, false );
		attempt( 'send', () => xhr.send() );
		attempt( 'second send', () => xhr.send() );
	},
};

scenarios[ scenario ]();
// A request that never ends shows as such in what is recorded.
await Promise.race( [
	ended,
	new Promise( ( resolve ) => setTimeout( resolve, 20000 ) ),
] );

let response;
try {
	response =
		xhr.responseType === 'json'
			? JSON.stringify( xhr.response )
			: xhr.responseText;
} catch ( error ) {
	response = `threw ${ error.name }`;
}

return JSON.stringify(
	{
		events,
		readyState: xhr.readyState,
		status: xhr.status,
		response,
		responseURL: xhr.responseURL,
	},
	null,
	2
);
