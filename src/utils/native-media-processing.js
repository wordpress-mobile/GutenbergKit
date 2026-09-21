/**
 * Internal dependencies
 */
import { getGBKit } from './bridge';
import { error as logError, info } from './logger';

const CHUNK_SIZE = 256 * 1024;
const MEDIA_UPLOAD_PATH = /^\/wp\/v2\/media(\?|$)/;

/**
 * Processes iOS media uploads before the normal WordPress REST request.
 *
 * @param {Object}   options API fetch options.
 * @param {Function} next    Next API fetch middleware.
 * @return {Promise<*>} The next middleware's result.
 */
export function nativeMediaProcessingMiddleware( options, next ) {
	if ( ! isEligibleUpload( options ) ) {
		return next( options );
	}

	const file = options.body.get( 'file' );
	if ( ! ( file instanceof File ) ) {
		return next( options );
	}

	return processFile( file, options.signal ).then( ( processedFile ) => {
		if ( ! processedFile ) {
			return next( options );
		}
		info(
			'Native media processing completed; uploading through WordPress.',
			{
				size: processedFile.size,
			}
		);
		return next( {
			...options,
			body: replaceFile( options.body, processedFile ),
		} );
	} );
}

/**
 * Streams a file through the native processing bridge and returns its output.
 *
 * @param {File}        file     The file to process.
 * @param {AbortSignal} [signal] Upload cancellation signal.
 * @return {Promise<File|null>} The processed file, or null when native declines.
 */
export async function processFile( file, signal ) {
	const id = crypto.randomUUID();
	let finished = false;
	let cleanedUp = false;
	let bridge;

	try {
		throwIfAborted( signal );
		bridge = getMediaProcessingBridge();
	} catch ( err ) {
		if ( signal?.aborted ) {
			throw abortError( signal );
		}
		logError( 'Native media processing failed', err );
		throw nativeProcessingError( err );
	}

	const cancel = () => {
		if ( cleanedUp ) {
			return;
		}
		cleanedUp = true;
		bridge( { action: 'cancel', id } ).catch( ( err ) =>
			logError( 'Native media processing cancellation failed', err )
		);
	};
	const abort = () => cancel();
	const pageHide = () => cancel();
	signal?.addEventListener( 'abort', abort, { once: true } );
	window.addEventListener( 'pagehide', pageHide, { once: true } );

	try {
		throwIfAborted( signal );
		const started = await awaitWithAbort(
			bridge( {
				action: 'begin',
				id,
				filename: file.name,
				mimeType: file.type,
				size: file.size,
			} ),
			signal
		);
		throwIfAborted( signal );

		if ( ! started?.accepted ) {
			cleanedUp = true;
			return null;
		}

		for ( let offset = 0; offset < file.size; offset += CHUNK_SIZE ) {
			const chunk = file.slice( offset, offset + CHUNK_SIZE );
			const data = await base64( chunk );
			throwIfAborted( signal );
			await awaitWithAbort(
				bridge( { action: 'append', id, offset, data } ),
				signal
			);
			throwIfAborted( signal );
		}

		const result = await awaitWithAbort(
			bridge( { action: 'finish', id } ),
			signal
		);
		finished = true;
		throwIfAborted( signal );
		const blob = await readBlob( result.url, signal );
		throwIfAborted( signal );
		if ( typeof result.size !== 'number' || blob.size !== result.size ) {
			throw new Error(
				'Processed media size does not match the native result.'
			);
		}
		await release( bridge, id );
		cleanedUp = true;

		return new File( [ blob ], result.filename, {
			type: result.mimeType || blob.type,
		} );
	} catch ( err ) {
		if ( signal?.aborted ) {
			throw abortError( signal );
		}
		logError( 'Native media processing failed', err );
		throw nativeProcessingError( err );
	} finally {
		signal?.removeEventListener( 'abort', abort );
		window.removeEventListener( 'pagehide', pageHide );
		if ( ! cleanedUp ) {
			if ( finished ) {
				await release( bridge, id );
			} else {
				cancel();
			}
		}
	}
}

function isEligibleUpload( options ) {
	const { nativeMediaProcessing } = getGBKit();
	return (
		nativeMediaProcessing === true &&
		options.method?.toUpperCase() === 'POST' &&
		MEDIA_UPLOAD_PATH.test( options.path || '' ) &&
		options.body instanceof FormData
	);
}

function getMediaProcessingBridge() {
	const handler = window.webkit?.messageHandlers?.mediaProcessing;
	if ( ! handler?.postMessage ) {
		throw new Error( 'Native media processing bridge is unavailable.' );
	}
	return ( message ) =>
		Promise.resolve().then( () => handler.postMessage( message ) );
}

function replaceFile( formData, file ) {
	const replacement = new FormData();
	for ( const [ key, value ] of formData.entries() ) {
		if ( key === 'file' ) {
			replacement.append( key, file, file.name );
		} else {
			replacement.append( key, value );
		}
	}
	return replacement;
}

async function base64( blob ) {
	const bytes = new Uint8Array( await blob.arrayBuffer() );
	let binary = '';
	for ( let index = 0; index < bytes.length; index += 8192 ) {
		binary += String.fromCharCode(
			...bytes.subarray( index, index + 8192 )
		);
	}
	return btoa( binary );
}

function readBlob( url, signal ) {
	return new Promise( ( resolve, reject ) => {
		const request = new XMLHttpRequest();
		let settled = false;
		const settle = ( callback, value ) => {
			if ( settled ) {
				return;
			}
			settled = true;
			signal?.removeEventListener( 'abort', abort );
			callback( value );
		};
		const abort = () => {
			request.abort();
			settle( reject, abortError( signal ) );
		};
		request.open( 'GET', url );
		request.responseType = 'blob';
		request.onload = () => {
			if ( request.status >= 200 && request.status < 300 ) {
				settle( resolve, request.response );
			} else {
				settle(
					reject,
					new Error( 'Processed media could not be read.' )
				);
			}
		};
		request.onerror = () =>
			settle( reject, new Error( 'Processed media could not be read.' ) );
		signal?.addEventListener( 'abort', abort, { once: true } );
		if ( signal?.aborted ) {
			abort();
			return;
		}
		request.send();
	} );
}

function awaitWithAbort( promise, signal ) {
	if ( ! signal ) {
		return promise;
	}
	if ( signal.aborted ) {
		return Promise.reject( abortError( signal ) );
	}
	return new Promise( ( resolve, reject ) => {
		const abort = () => {
			signal.removeEventListener( 'abort', abort );
			reject( abortError( signal ) );
		};
		signal.addEventListener( 'abort', abort, { once: true } );
		promise.then(
			( value ) => {
				signal.removeEventListener( 'abort', abort );
				resolve( value );
			},
			( err ) => {
				signal.removeEventListener( 'abort', abort );
				reject( err );
			}
		);
	} );
}

async function release( bridge, id ) {
	try {
		await bridge( { action: 'release', id } );
	} catch ( err ) {
		logError( 'Native media processing release failed', err );
	}
}

function throwIfAborted( signal ) {
	if ( signal?.aborted ) {
		throw abortError( signal );
	}
}

function abortError( signal ) {
	return (
		signal.reason ??
		new DOMException( 'The upload was aborted.', 'AbortError' )
	);
}

function nativeProcessingError( err ) {
	return {
		code: 'native_media_processing_error',
		message: err?.message || 'Native media processing failed.',
	};
}
