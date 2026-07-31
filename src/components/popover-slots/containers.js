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

/**
 * Retrieves a body-level popover container by ID.
 *
 * The containers are declared in `index.html` so their styles apply before the
 * editor mounts.
 *
 * @param {string} id The container element ID.
 *
 * @return {HTMLElement|null} The container element, or null if absent.
 */
function getContainer( id ) {
	return document.getElementById( id );
}
