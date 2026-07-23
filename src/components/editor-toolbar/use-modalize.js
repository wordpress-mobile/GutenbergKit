/**
 * WordPress dependencies
 */
import { useEffect } from '@wordpress/element';

/**
 * Internal dependencies
 */
import * as ariaHelper from './aria-helper';
import {
	getClipContainer,
	getOverlayContainer,
} from '../popover-slots/containers';

/** @typedef {import('@wordpress/element').RefObject} RefObject */

/**
 * Conditionally hides the document from screen readers, except for the
 * element provided—or, by default, the containers popovers render into.
 *
 * Both popover containers are kept accessible rather than the individual open
 * popover. Only one modal popover is open at a time, and neither container
 * holds editor content, so hiding one of them gains nothing.
 *
 * @param {boolean}   isModalVisible A boolean indicating whether the modal is visible.
 * @param {RefObject} elementRef     A reference to the DOM element to be modalized.
 */
export function useModalize( isModalVisible, elementRef ) {
	useEffect( () => {
		if ( ! isModalVisible ) {
			return;
		}

		const element = elementRef?.current;
		if ( element ) {
			ariaHelper.modalize( element );
		} else {
			ariaHelper.modalize( getClipContainer(), getOverlayContainer() );
		}

		return () => {
			ariaHelper.unmodalize();
		};
	}, [ elementRef, isModalVisible ] );
}
