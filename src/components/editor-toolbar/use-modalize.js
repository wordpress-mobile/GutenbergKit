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
export function useModalize(isModalVisible, elementRef = defaultPopover()) {
	useEffect(() => {
		if (isModalVisible) {
			ariaHelper.modalize(elementRef.current);
		} else {
			ariaHelper.unmodalize();
		}
	}, [elementRef, isModalVisible]);
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
 * @return {Object} An object containing the current `popoverFallbackContainerRef`.
 */
function defaultPopover() {
	if (popoverFallbackContainerRef.current) {
		return popoverFallbackContainerRef;
	}

	popoverFallbackContainerRef.current = document.getElementById(
		'popover-fallback-container'
	);

	return popoverFallbackContainerRef;
}
