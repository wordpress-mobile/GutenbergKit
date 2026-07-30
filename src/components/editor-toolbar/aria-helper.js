/**
 * This file was sourced from the Gutenberg project and converted from
 * TypeScript to JavaScript.
 *
 * @see https://github.com/WordPress/gutenberg/blob/3f0a805c568f92622faf4b71b24eeb5f39b5bca8/packages/components/src/modal/aria-helper.ts
 */

const LIVE_REGION_ARIA_ROLES = new Set( [
	'alert',
	'status',
	'log',
	'marquee',
	'timer',
] );

const hiddenElementBatches = [];

/**
 * Hides all elements in the body element from screen-readers except
 * the provided elements, their ancestors, and elements that should not be
 * hidden from screen-readers.
 *
 * Elements are hidden by walking from each modal element up to the body and
 * hiding the other children of every ancestor along the way. Hiding only the
 * body's children would be insufficient, as a modal element is not
 * necessarily a body child—popovers render into slots nested within
 * body-level containers.
 *
 * The reason we do this is because `aria-modal="true"` currently is bugged
 * in Safari, and support is spotty in other browsers overall. In the future
 * we should consider removing these helper functions in favor of
 * `aria-modal="true"`.
 *
 * @param {...Element} modalElements The elements that should not be hidden.
 *
 * @return {Set<Element>} A handle identifying the elements hidden by this call,
 *                        to be passed to `unmodalize`.
 */
export function modalize( ...modalElements ) {
	// A Set, so overlapping ancestor chains do not record an element twice, and
	// so `unmodalize` can remove this batch by identity regardless of the order
	// in which overlapping modals close.
	const hiddenElements = new Set();
	hiddenElementBatches.push( hiddenElements );

	const elements = modalElements.filter(
		( element ) => element?.isConnected
	);
	// Ancestors of a modal element must stay accessible, otherwise the modal
	// element is hidden along with them.
	const visibleElements = new Set();
	for ( const modalElement of elements ) {
		for (
			let element = modalElement;
			element && element !== document.body;
			element = element.parentElement
		) {
			visibleElements.add( element );
		}
	}

	for ( const modalElement of elements ) {
		for (
			let element = modalElement;
			element?.parentElement && element !== document.body;
			element = element.parentElement
		) {
			for ( const sibling of element.parentElement.children ) {
				if (
					visibleElements.has( sibling ) ||
					! elementShouldBeHidden( sibling )
				) {
					continue;
				}

				sibling.setAttribute( 'aria-hidden', 'true' );
				hiddenElements.add( sibling );
			}
		}
	}

	return hiddenElements;
}
/**
 * Determines if the passed element should not be hidden from screen readers.
 *
 * @param {Element} element The element that should be checked.
 *
 * @return {boolean} Whether the element should not be hidden from screen-readers.
 */
export function elementShouldBeHidden( element ) {
	const role = element.getAttribute( 'role' );
	return ! (
		element.tagName === 'SCRIPT' ||
		element.hasAttribute( 'hidden' ) ||
		element.hasAttribute( 'aria-hidden' ) ||
		element.hasAttribute( 'aria-live' ) ||
		( role && LIVE_REGION_ARIA_ROLES.has( role ) )
	);
}

/**
 * Accessibly reveals the elements hidden by a modal.
 *
 * The batch to reveal is identified by the handle `modalize` returned, rather
 * than assuming the most recent modal closes first. Modals do not always close
 * in the reverse of the order they opened—the block inserter and the block
 * settings menu can be open together—and React runs effect cleanups in
 * hook-declaration order, not reverse-open order.
 *
 * @param {Set<Element>} handle The handle returned by `modalize`. Defaults to
 *                              the most recent batch for backward
 *                              compatibility.
 */
export function unmodalize( handle = hiddenElementBatches.at( -1 ) ) {
	const index = hiddenElementBatches.lastIndexOf( handle );
	if ( index === -1 ) {
		return;
	}

	hiddenElementBatches.splice( index, 1 );

	for ( const element of handle ) {
		// Keep the element hidden if another open modal still hides it.
		const stillHidden = hiddenElementBatches.some( ( batch ) =>
			batch.has( element )
		);
		if ( ! stillHidden ) {
			element.removeAttribute( 'aria-hidden' );
		}
	}
}
