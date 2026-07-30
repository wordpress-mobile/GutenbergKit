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
 * With no `elementRef`, both popover containers are kept accessible rather than
 * a single open popover: every editor popover renders into one of the two, and
 * neither container holds editor content, so keeping both reachable is
 * harmless. Pass `elementRef` to modalize around a specific element instead—
 * e.g. a modal mounted outside those containers that should sit above them.
 *
 * Multiple modals may be open at once (the block inserter and the block
 * settings menu, for example), so each call is reversed by the handle
 * `modalize` returns rather than by close order. See `./aria-helper.js`.
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
		const handle = element
			? ariaHelper.modalize( element )
			: ariaHelper.modalize( getClipContainer(), getOverlayContainer() );

		return () => {
			ariaHelper.unmodalize( handle );
		};
	}, [ elementRef, isModalVisible ] );
}
