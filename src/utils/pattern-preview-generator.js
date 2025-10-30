/**
 * WordPress dependencies
 */
import { parse, serialize } from '@wordpress/blocks';

/**
 * Internal dependencies
 */
import { debug } from './logger';

// Lazy load html2canvas to avoid bundling if not needed
let html2canvas = null;

/**
 * Loads html2canvas library dynamically
 *
 * @return {Promise<Function>} The html2canvas function
 */
async function loadHtml2Canvas() {
	if ( html2canvas ) {
		return html2canvas;
	}

	try {
		const module = await import( 'html2canvas' );
		html2canvas = module.default;
		return html2canvas;
	} catch ( error ) {
		debug( 'Failed to load html2canvas:', error );
		throw new Error( 'html2canvas library not available' );
	}
}

/**
 * Generates a preview image data URL for a pattern
 *
 * @param {Object} pattern               Pattern object with content and viewportWidth
 * @param {string} pattern.content       Serialized block HTML
 * @param {number} pattern.viewportWidth Preview viewport width (default 1200)
 * @return {Promise<string|null>}        Data URL of the preview image or null if generation fails
 */
export async function generatePatternPreview( pattern ) {
	const { content, viewportWidth = 1200 } = pattern;

	if ( ! content ) {
		debug( 'Pattern has no content, cannot generate preview' );
		return null;
	}

	try {
		// Parse the pattern content to get blocks
		const blocks = parse( content, {
			__unstableSkipMigrationLogs: true,
		} );

		if ( ! blocks || blocks.length === 0 ) {
			debug( 'Pattern has no blocks, cannot generate preview' );
			return null;
		}

		// Create off-screen container
		const container = document.createElement( 'div' );
		container.style.position = 'absolute';
		container.style.left = '-9999px';
		container.style.top = '0';
		container.style.width = `${ Math.min( viewportWidth, 800 ) }px`; // Cap at 800px for performance
		container.style.backgroundColor = '#ffffff';
		container.style.padding = '20px';
		container.style.boxSizing = 'border-box';
		document.body.appendChild( container );

		// Use WordPress serialize function to get the actual HTML representation
		// This properly renders blocks using their save functions
		const serializedContent = serialize( blocks );

		container.innerHTML = serializedContent;

		// Wait for any styles to apply
		await new Promise( ( resolve ) => {
			requestAnimationFrame( () => {
				requestAnimationFrame( resolve );
			} );
		} );

		// Load html2canvas
		const html2canvasFn = await loadHtml2Canvas();

		// Capture as canvas
		const canvas = await html2canvasFn( container, {
			backgroundColor: '#ffffff',
			scale: 1,
			logging: false,
			width: container.offsetWidth,
			height: Math.min( container.offsetHeight, 600 ), // Cap height at 600px
			windowWidth: container.offsetWidth,
			windowHeight: container.offsetHeight,
		} );

		// Convert to data URL with compression
		const dataURL = canvas.toDataURL( 'image/jpeg', 0.7 );

		// Cleanup
		document.body.removeChild( container );

		debug(
			`Generated preview for pattern, size: ${ dataURL.length } bytes`
		);

		return dataURL;
	} catch ( error ) {
		debug( 'Failed to generate pattern preview:', error );
		return null;
	}
}
