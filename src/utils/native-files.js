/**
 * Files native code hands the page.
 *
 * The native block inserter imports a picked photo or video to disk. The page
 * needs it as a `File`: Gutenberg's upload pipeline, and any block that uploads
 * on its own, reads the bytes from one. Fetching the file into a `Blob` would
 * hold all of it in the page's memory, which a large video does not fit.
 *
 * So the page clicks a file input, and native code answers the open panel WebKit
 * would otherwise show with the files it holds. The page gets what the system
 * picker gives it: `File`s that WebKit reads from disk as they are sliced.
 */

/**
 * How long to wait for native code to answer before giving up, in milliseconds.
 * It answers at once, so this only bounds a host that never answers.
 */
const NATIVE_FILES_TIMEOUT = 10000;

/**
 * Asks native code for the files it is offering.
 *
 * Call this synchronously from the script native code runs: the click needs the
 * user activation that script carries, and an `await` before it loses it.
 *
 * @param {Object} options
 * @param {number} options.timeout How long to wait for the files, in milliseconds.
 * @return {Promise<File[]>} The files, in the order native code offered them.
 *                           Rejects when native code offers none.
 */
export function requestNativeFiles( { timeout = NATIVE_FILES_TIMEOUT } = {} ) {
	return new Promise( ( resolve, reject ) => {
		const input = document.createElement( 'input' );
		input.type = 'file';
		input.multiple = true;
		input.style.display = 'none';

		const settle = ( outcome, value ) => {
			clearTimeout( timer );
			input.remove();
			outcome( value );
		};
		const unavailable = () =>
			new Error( 'Native code did not provide the files' );
		const timer = setTimeout(
			() => settle( reject, unavailable() ),
			timeout
		);

		input.addEventListener( 'change', () => {
			const files = Array.from( input.files ?? [] );
			if ( files.length === 0 ) {
				settle( reject, unavailable() );
			} else {
				settle( resolve, files );
			}
		} );
		input.addEventListener( 'cancel', () =>
			settle( reject, unavailable() )
		);

		document.body.appendChild( input );
		input.click();
	} );
}

/**
 * `file` with `type` as its MIME type, when WebKit could not tell the type from
 * the file's name. Wrapping a file-backed `File` keeps it file-backed.
 *
 * @param {File}    file The file native code provided.
 * @param {?string} type The MIME type native code reported.
 * @return {File} The file, typed.
 */
export function withMimeType( file, type ) {
	if ( file.type || ! type ) {
		return file;
	}
	return new File( [ file ], file.name, {
		type,
		lastModified: file.lastModified,
	} );
}
