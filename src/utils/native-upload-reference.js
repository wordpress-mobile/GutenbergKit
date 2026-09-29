/**
 * WordPress dependencies
 */
import { __, sprintf } from '@wordpress/i18n';

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

/**
 * Builds the stand-in for a media item the native inserter imported.
 *
 * Only the preview crosses into the page. Rejects, with core's own message, a
 * file larger than the site accepts: the stand-in is small, so core's size
 * check would pass it and native code would upload a file WordPress refuses.
 *
 * @param {Object}   media                     The inserter's media item.
 * @param {Object}   media.nativeUpload        What native code registered.
 * @param {?string}  media.type                The file's MIME type.
 * @param {Object}   options
 * @param {?number}  options.maxUploadFileSize The site's upload limit, in bytes.
 * @param {Function} options.fetchPreview      Loads the preview; `fetch` by default.
 * @return {Promise<File>} The stand-in.
 */
export async function standInForNativeUpload(
	media,
	{ maxUploadFileSize = null, fetchPreview = ( url ) => fetch( url ) } = {}
) {
	const { sessionId, filename, size, previewUrl } = media.nativeUpload;
	if ( maxUploadFileSize && size > maxUploadFileSize ) {
		const error = new Error(
			sprintf(
				// translators: %s: file name.
				__(
					'%s: This file exceeds the maximum upload size for this site.'
				),
				filename
			)
		);
		error.code = 'SIZE_ABOVE_LIMIT';
		throw error;
	}

	let preview = null;
	if ( previewUrl ) {
		try {
			preview = await ( await fetchPreview( previewUrl ) ).blob();
		} catch {
			// The block shows no preview while it uploads; the upload is unaffected.
		}
	}

	return createNativeUploadStandIn( {
		sessionId,
		filename,
		type: media.type ?? 'application/octet-stream',
		preview,
	} );
}
