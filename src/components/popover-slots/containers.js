/**
 * Name of the slot rendering popovers that must not be clipped—namely the
 * full-screen block settings menu. Pass it to a `Popover` via
 * `__unstableSlotName`.
 *
 * @type {string}
 */
export const OVERLAY_SLOT_NAME = 'gutenberg-kit-overlay';

/**
 * Retrieves the container clipping popovers to the viewport.
 *
 * @return {HTMLElement} The clipping container element.
 */
export function getClipContainer() {
	return getContainer( 'popover-clip-container' );
}

/**
 * Retrieves the container rendering popovers that must not be clipped.
 *
 * @return {HTMLElement} The overlay container element.
 */
export function getOverlayContainer() {
	return getContainer( 'popover-overlay-container' );
}

const containers = new Map();

/**
 * Retrieves a body-level popover container by ID, creating it when absent.
 *
 * The containers are declared in `index.html` so their styles apply before the
 * editor mounts. They are created here as a fallback for environments that
 * render the editor into a different document—e.g. tests.
 *
 * @param {string} id The container element ID.
 *
 * @return {HTMLElement} The container element.
 */
function getContainer( id ) {
	if ( containers.get( id )?.isConnected ) {
		return containers.get( id );
	}

	let container = document.getElementById( id );
	if ( ! container ) {
		container = document.createElement( 'div' );
		container.id = id;
		document.body.append( container );
	}

	containers.set( id, container );

	return container;
}
