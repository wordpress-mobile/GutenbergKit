/**
 * Hook to manage scroll indicator state for horizontally scrollable containers.
 *
 * The `canScroll*` properties describe the physical edges of the container
 * rather than the start and end of the content, matching the gradients they
 * drive. Those are anchored with `left`/`right` and do not flip in a
 * right-to-left layout.
 *
 * @param {Object} scrollRef - React ref to the scrollable container element
 * @return {Object} Scroll state with properties:
 *   - isScrollable: Whether the container has overflow content
 *   - canScrollLeft: Whether there's content hidden past the left edge
 *   - canScrollRight: Whether there's content hidden past the right edge
 */

import { useState, useEffect, useCallback } from '@wordpress/element';

export function useScrollIndicators( scrollRef ) {
	const [ scrollState, setScrollState ] = useState( {
		isScrollable: false,
		canScrollLeft: false,
		canScrollRight: false,
	} );

	const updateScrollState = useCallback( () => {
		const element = scrollRef.current;
		if ( ! element ) {
			return;
		}

		const { scrollLeft, scrollWidth, clientWidth } = element;

		// Small threshold to account for rounding errors
		const threshold = 1;

		const isScrollable = scrollWidth > clientWidth;

		// In a right-to-left container `scrollLeft` is `0` at the right edge
		// and grows negative moving left, so the raw value describes distance
		// from the start rather than from the left. Normalize to that distance,
		// then map it back onto the physical edges the gradients are anchored
		// to, which do not flip with the writing direction.
		const distanceFromStart = Math.abs( scrollLeft );
		const distanceFromEnd = scrollWidth - clientWidth - distanceFromStart;

		// Read from the document rather than resolving the element's computed
		// style, which this would otherwise force on every scroll frame. The
		// direction is set once at startup and fixed for the editor's lifetime.
		const isRTL = element.ownerDocument.documentElement.dir === 'rtl';

		const canScrollLeft =
			( isRTL ? distanceFromEnd : distanceFromStart ) > threshold;
		const canScrollRight =
			( isRTL ? distanceFromStart : distanceFromEnd ) > threshold;

		setScrollState( {
			isScrollable,
			canScrollLeft,
			canScrollRight,
		} );
	}, [ scrollRef ] );

	useEffect( () => {
		const element = scrollRef.current;
		if ( ! element ) {
			return;
		}

		updateScrollState(); // Initial state

		element.addEventListener( 'scroll', updateScrollState );
		window.addEventListener( 'resize', updateScrollState );

		let resizeObserver;
		if ( typeof ResizeObserver !== 'undefined' ) {
			resizeObserver = new ResizeObserver( updateScrollState );
			resizeObserver.observe( element );
		}

		return () => {
			element.removeEventListener( 'scroll', updateScrollState );
			window.removeEventListener( 'resize', updateScrollState );
			if ( resizeObserver ) {
				resizeObserver.disconnect();
			}
		};
	}, [ scrollRef, updateScrollState ] );

	return scrollState;
}
