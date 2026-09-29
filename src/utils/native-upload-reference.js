/**
 * Stand-in files for media native code already holds.
 *
 * The native block inserter imports a picked photo or video to disk and uploads it
 * from there, so the file's bytes never enter the page — a large video would not
 * fit. Gutenberg's upload pipeline still needs a `File` to show a placeholder, lock
 * saving, and report errors, so the page gets a stand-in: a small preview image (or
 * nothing) followed by a marker naming the native upload session.
 *
 * The marker travels in the bytes because nothing else survives the trip: core
 * re-creates the `File` when it builds the upload's `FormData`, which drops object
 * identity and any property set on it, but keeps the bytes, name, and type.
 */

const MARKER = '\nGBK-NATIVE-UPLOAD:';
const SESSION_ID_PATTERN =
	/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const MARKER_LENGTH = MARKER.length + 36;

/**
 * Creates a stand-in for a file native code will upload.
 *
 * @param {Object}    options
 * @param {string}    options.sessionId The native upload session to finish.
 * @param {string}    options.filename  The real file's name.
 * @param {string}    options.type      The real file's MIME type.
 * @param {Blob|null} options.preview   An image to show while the upload runs.
 * @return {File} The stand-in.
 */
export function createNativeUploadStandIn( {
	sessionId,
	filename,
	type,
	preview = null,
} ) {
	const parts = preview ? [ preview ] : [];
	parts.push( `${ MARKER }${ sessionId }` );
	return new File( parts, filename, { type } );
}

/**
 * The native upload session a stand-in names, or `null` for an ordinary file.
 *
 * Reads only the file's last few bytes, so it is cheap for a file of any size.
 *
 * @param {Blob} file The file to check.
 * @return {Promise<?string>} The session ID.
 */
export async function readNativeUploadReference( file ) {
	if ( file.size < MARKER_LENGTH ) {
		return null;
	}
	const tail = await file.slice( file.size - MARKER_LENGTH ).text();
	if ( ! tail.startsWith( MARKER ) ) {
		return null;
	}
	const sessionId = tail.slice( MARKER.length );
	return SESSION_ID_PATTERN.test( sessionId ) ? sessionId : null;
}
