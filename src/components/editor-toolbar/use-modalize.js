/**
 * WordPress dependencies
 */
import { useEffect } from '@wordpress/element';

/**
 * Internal dependencies
 */
import * as ariaHelper from './aria-helper';

/** @typedef {import('@wordpress/element').RefObject} RefObject */

/**
 * Conditionally applies the `aria-hidden` attribute to all direct decendents of
 * the body element, except for the element provided.
 *
 * @param {boolean}   isModalVisible A boolean indicating whether the modal is visible.
 * @param {RefObject} elementRef     A reference to the DOM element to be modalized.
 */
export function useModalize( isModalVisible, elementRef = defaultPopover() ) {
	useEffect( () => {
		if ( isModalVisible ) {
			ariaHelper.modalize( elementRef.current );
		} else {
			ariaHelper.unmodalize();
		}
	}, [ elementRef, isModalVisible ] );
}

const popoverFallbackContainerRef = { current: null };

/**
 * Retrieves or initializes the fallback container for popovers.
 *
 * This function checks if the `popoverFallbackContainerRef` is already defined.
 * If not, it attempts to find an element with the class name
 * 'components-popover__fallback-container' in the document and assigns it to
 * `popoverFallbackContainerRef`. It then returns an object with the current
 * `popoverFallbackContainerRef`.
 *
 * This relies on popovers rendering into Gutenberg's default fallback
 * container, which is a direct child of the body and a sibling of `#root`.
 * `modalize` hides every other body child from screen readers while keeping
 * this container—and thus the active popover—accessible. Do not relocate
 * popovers into a `Popover.Slot` inside the editor: a slot within `#root`
 * would place popovers under an element that `modalize` marks inert, hiding
 * their contents. This is also why the body clips popover overflow (with
 * `.gutenberg-kit-root` owning vertical scroll) rather than the editor
 * container. See `../../index.scss`.
 *
 * @return {Object} An object containing the current `popoverFallbackContainerRef`.
 */
function defaultPopover() {
	if ( popoverFallbackContainerRef.current ) {
		return popoverFallbackContainerRef;
	}

	popoverFallbackContainerRef.current = document.getElementById(
		'popover-fallback-container'
	);

	return popoverFallbackContainerRef;
}
