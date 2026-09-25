/**
 * Removes any trailing slashes from a URL or path.
 *
 * An absent value normalizes to an empty string, so an unset config field can
 * be handed over directly. Any other non-string still throws, so a wrong type
 * is not quietly passed through.
 *
 * @param {string} [value] The URL or path to normalize.
 * @return {string} The value without a trailing slash.
 */
export function stripTrailingSlash( value ) {
	return ( value ?? '' ).replace( /\/+$/, '' );
}

/**
 * Normalizes a URL or path to exactly one trailing slash.
 *
 * An absent value stays absent rather than becoming a lone slash, which would
 * resolve requests against the page root. A value that is already just `/` is
 * kept, since that is a meaningful root.
 *
 * @param {string} [value] The URL or path to normalize.
 * @return {string} The value with a single trailing slash, or an empty string.
 */
export function ensureTrailingSlash( value ) {
	if ( value === undefined || value === null || value === '' ) {
		return '';
	}

	return `${ stripTrailingSlash( value ) }/`;
}
