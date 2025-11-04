/**
 * Hook to manage scroll indicator state for horizontally scrollable containers.
 *
 * @param {Object} scrollRef - React ref to the scrollable container element
 * @return {Object} Scroll state with properties:
 *   - isScrollable: Whether the container has overflow content
 *   - canScrollLeft: Whether there's content to the left (not at start)
 *   - canScrollRight: Whether there's content to the right (not at end)
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
		const canScrollLeft = scrollLeft > threshold;
		const canScrollRight =
			scrollLeft + clientWidth < scrollWidth - threshold;

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
