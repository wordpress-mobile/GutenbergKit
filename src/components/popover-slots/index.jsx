/**
 * WordPress dependencies
 */
import { createPortal } from '@wordpress/element';
import { Popover } from '@wordpress/components';

/**
 * Internal dependencies
 */
import './style.scss';
import {
	OVERLAY_SLOT_NAME,
	getClipContainer,
	getOverlayContainer,
} from './containers';

/**
 * Renders the slots that receive the editor's popovers.
 *
 * Popovers otherwise render into Gutenberg's fallback container, a body child
 * positioned relative to the viewport. A popover anchored near the right
 * edge—such as the block toolbar's "Options" menu after the toolbar is
 * scrolled—extends past the viewport and grows the document's scrollable
 * width, letting the canvas be swiped horizontally to reveal the empty
 * background behind it.
 *
 * Two slots are rendered rather than one because the two kinds of popovers
 * have opposing requirements:
 *
 * - Dropdown popovers must be clipped to the viewport. They render into the
 *   default slot, which lives in a fixed, `overflow: hidden` container. Being
 *   out of flow, that container clips the overflow without contributing to
 *   the document's scrollable size, so the document remains the scroll
 *   container.
 * - The full-screen block settings menu must not be clipped. WebKit renders a
 *   `position: fixed` element semi-transparent when an ancestor clips its
 *   overflow, so the settings menu opts into its own slot in an unclipped
 *   container via `__unstableSlotName`. It fills the viewport and never
 *   overflows, so it does not need clipping.
 *
 * Both containers are body children so `modalize` can keep the active popover
 * accessible while marking the rest of the document inert. See
 * `../editor-toolbar/use-modalize.js`.
 *
 * @return {Element} The rendered popover slots.
 */
export default function PopoverSlots() {
	return (
		<>
			{ createPortal( <Popover.Slot />, getClipContainer() ) }
			{ createPortal(
				<Popover.Slot name={ OVERLAY_SLOT_NAME } />,
				getOverlayContainer()
			) }
		</>
	);
}
