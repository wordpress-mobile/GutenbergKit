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

/**
 * While a modal is visible, hides everything from screen readers except the
 * containers popovers render into.
 *
 * Every editor popover renders into one of the two containers, and neither
 * holds editor content, so keeping both reachable while hiding the rest of the
 * document is what an open popover needs.
 *
 * Multiple modals may be open at once (the block inserter and the block
 * settings menu, for example), so each call is reversed by the handle
 * `modalize` returns rather than by close order. See `./aria-helper.js`.
 *
 * @param {boolean} isModalVisible Whether the modal is visible.
 */
export function useModalize( isModalVisible ) {
	useEffect( () => {
		if ( ! isModalVisible ) {
			return;
		}

		const handle = ariaHelper.modalize(
			getClipContainer(),
			getOverlayContainer()
		);

		return () => {
			ariaHelper.unmodalize( handle );
		};
	}, [ isModalVisible ] );
}
