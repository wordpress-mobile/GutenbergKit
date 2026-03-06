/**
 * WordPress dependencies
 */
import { dispatch } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';
import { store as editorStore } from '@wordpress/editor';

/**
 * Internal dependencies
 */
import { getGBKit } from './bridge';
import { error as logError, debug } from './logger';

/**
 * Unique lock name for post saving during native uploads.
 */
const UPLOAD_LOCK = 'native-upload';

/**
 * Creates a `mediaUpload` override that routes files through a local HTTP
 * server running on the native host. Returns `null` when the native upload
 * server is not configured, signalling the caller to preserve default behavior.
 *
 * @return {Function|null} The mediaUpload override, or null if not configured.
 */
export function createNativeMediaUpload() {
	const { nativeUploadPort, nativeUploadToken } = getGBKit();

	if ( ! nativeUploadPort ) {
		return null;
	}

	return ( { filesList, onFileChange, onError, allowedTypes } ) => {
		nativeMediaUpload( {
			filesList,
			onFileChange,
			onError,
			allowedTypes,
			port: nativeUploadPort,
			token: nativeUploadToken,
		} );
	};
}

/**
 * Uploads files through the native host's local HTTP server.
 *
 * 1. Creates blob preview URLs and delivers them to the block immediately.
 * 2. Locks post saving to prevent saving while uploads are in progress.
 * 3. POSTs each file to the local server.
 * 4. On success: revokes blob URLs, unlocks saving, updates the entity cache,
 *    and delivers the final media objects to the block.
 * 5. On failure: cleans up blob URLs, unlocks saving, and calls onError.
 *
 * @param {Object}   options
 * @param {FileList} options.filesList    The files to upload.
 * @param {Function} options.onFileChange Callback receiving media objects.
 * @param {Function} options.onError      Callback receiving error messages.
 * @param {string[]} options.allowedTypes Allowed MIME type prefixes (e.g. ['image']).
 * @param {number}   options.port         Local server port.
 * @param {string}   options.token        Auth token for the local server.
 */
async function nativeMediaUpload( {
	filesList,
	onFileChange,
	onError,
	allowedTypes,
	port,
	token,
} ) {
	const files = filterByAllowedTypes( Array.from( filesList ), allowedTypes );

	if ( files.length === 0 ) {
		return;
	}

	const blobURLs = files.map( ( file ) => URL.createObjectURL( file ) );

	// Deliver blob previews for immediate block feedback.
	const previews = files.map( ( file, i ) => ( {
		url: blobURLs[ i ],
		mime: file.type,
		type: getMimePrefix( file.type ),
	} ) );
	onFileChange( previews );

	dispatch( editorStore ).lockPostSaving( UPLOAD_LOCK );

	try {
		const results = await Promise.all(
			files.map( ( file ) => uploadFile( file, port, token ) )
		);

		blobURLs.forEach( ( url ) => URL.revokeObjectURL( url ) );
		dispatch( editorStore ).unlockPostSaving( UPLOAD_LOCK );

		// Update the entity cache so Gutenberg knows about the new media.
		results.forEach( ( media ) => {
			dispatch( coreStore ).receiveEntityRecords(
				'root',
				'media',
				media
			);
		} );

		onFileChange( results );
	} catch ( err ) {
		blobURLs.forEach( ( url ) => URL.revokeObjectURL( url ) );
		dispatch( editorStore ).unlockPostSaving( UPLOAD_LOCK );

		logError( 'Native upload failed', err );
		onError( err.message || 'Upload failed.' );
	}
}

/**
 * POSTs a single file to the native local HTTP server.
 *
 * @param {File}   file  The file to upload.
 * @param {number} port  Local server port.
 * @param {string} token Auth token.
 * @return {Promise<Object>} The media object returned by the server.
 */
async function uploadFile( file, port, token ) {
	const formData = new FormData();
	formData.append( 'file', file, file.name );

	debug( `Uploading ${ file.name } to native server on port ${ port }` );

	const response = await fetch( `http://localhost:${ port }/upload`, {
		method: 'POST',
		headers: { Authorization: `Bearer ${ token }` },
		body: formData,
	} );

	if ( ! response.ok ) {
		const body = await response.text().catch( () => '' );
		throw new Error(
			`Upload failed (${ response.status }): ${
				body || response.statusText
			}`
		);
	}

	return await response.json();
}

/**
 * Filters files by allowed MIME type prefixes.
 *
 * @param {File[]}   files        The files to filter.
 * @param {string[]} allowedTypes Allowed MIME type prefixes (e.g. ['image', 'video']).
 * @return {File[]} Filtered files.
 */
function filterByAllowedTypes( files, allowedTypes ) {
	if ( ! allowedTypes || allowedTypes.length === 0 ) {
		return files;
	}

	return files.filter( ( file ) =>
		allowedTypes.some( ( type ) => file.type.startsWith( type ) )
	);
}

/**
 * Extracts the MIME type prefix (e.g. 'image' from 'image/jpeg').
 *
 * @param {string} mimeType Full MIME type string.
 * @return {string} The prefix before the slash.
 */
function getMimePrefix( mimeType ) {
	return mimeType ? mimeType.split( '/' )[ 0 ] : '';
}
