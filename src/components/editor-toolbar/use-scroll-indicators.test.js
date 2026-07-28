/**
 * External dependencies
 */
import { describe, it, expect } from 'vitest';
import { renderHook } from '@testing-library/react';

/**
 * Internal dependencies
 */
import { useScrollIndicators } from './use-scroll-indicators';

/**
 * Builds a ref to an element with a stubbed scroll geometry.
 *
 * jsdom does not lay out content, so `scrollWidth` and `clientWidth` are always
 * `0` and the hook would see every container as unscrollable. Define them
 * directly to model an overflowing toolbar.
 *
 * @param {Object} geometry             Scroll geometry to simulate.
 * @param {number} geometry.scrollLeft  Current scroll offset. Negative in a
 *                                      right-to-left container.
 * @param {number} geometry.scrollWidth Total scrollable width.
 * @param {number} geometry.clientWidth Visible width.
 * @param {string} geometry.direction   Computed `direction` of the container.
 *
 * @return {Object} A React ref pointing at the element.
 */
function createScrollRef( {
	scrollLeft,
	scrollWidth = 500,
	clientWidth = 200,
	direction = 'ltr',
} ) {
	const element = document.createElement( 'div' );
	element.dir = direction;
	document.body.appendChild( element );

	Object.defineProperties( element, {
		scrollLeft: { value: scrollLeft, configurable: true },
		scrollWidth: { value: scrollWidth, configurable: true },
		clientWidth: { value: clientWidth, configurable: true },
	} );

	return { current: element };
}

describe( 'useScrollIndicators', () => {
	it( 'reports an overflowing container as scrollable', () => {
		const scrollRef = createScrollRef( { scrollLeft: 0 } );
		const { result } = renderHook( () => useScrollIndicators( scrollRef ) );

		expect( result.current.isScrollable ).toBe( true );
	} );

	it( 'reports a container without overflow as not scrollable', () => {
		const scrollRef = createScrollRef( {
			scrollLeft: 0,
			scrollWidth: 200,
			clientWidth: 200,
		} );
		const { result } = renderHook( () => useScrollIndicators( scrollRef ) );

		expect( result.current.isScrollable ).toBe( false );
		expect( result.current.canScrollLeft ).toBe( false );
		expect( result.current.canScrollRight ).toBe( false );
	} );

	describe( 'left-to-right', () => {
		it( 'hides the left gradient at the start edge', () => {
			const scrollRef = createScrollRef( { scrollLeft: 0 } );
			const { result } = renderHook( () =>
				useScrollIndicators( scrollRef )
			);

			expect( result.current.canScrollLeft ).toBe( false );
			expect( result.current.canScrollRight ).toBe( true );
		} );

		it( 'shows both gradients mid-scroll', () => {
			const scrollRef = createScrollRef( { scrollLeft: 150 } );
			const { result } = renderHook( () =>
				useScrollIndicators( scrollRef )
			);

			expect( result.current.canScrollLeft ).toBe( true );
			expect( result.current.canScrollRight ).toBe( true );
		} );

		it( 'hides the right gradient at the end edge', () => {
			const scrollRef = createScrollRef( { scrollLeft: 300 } );
			const { result } = renderHook( () =>
				useScrollIndicators( scrollRef )
			);

			expect( result.current.canScrollLeft ).toBe( true );
			expect( result.current.canScrollRight ).toBe( false );
		} );
	} );

	// `scrollLeft` is `0` at the right edge and grows negative moving left, so
	// the start edge is on the right and the gradients map to the opposite
	// physical edges from their left-to-right counterparts.
	describe( 'right-to-left', () => {
		it( 'hides the right gradient at the start edge', () => {
			const scrollRef = createScrollRef( {
				scrollLeft: 0,
				direction: 'rtl',
			} );
			const { result } = renderHook( () =>
				useScrollIndicators( scrollRef )
			);

			expect( result.current.canScrollRight ).toBe( false );
			expect( result.current.canScrollLeft ).toBe( true );
		} );

		it( 'shows both gradients mid-scroll', () => {
			const scrollRef = createScrollRef( {
				scrollLeft: -150,
				direction: 'rtl',
			} );
			const { result } = renderHook( () =>
				useScrollIndicators( scrollRef )
			);

			expect( result.current.canScrollLeft ).toBe( true );
			expect( result.current.canScrollRight ).toBe( true );
		} );

		it( 'hides the left gradient at the end edge', () => {
			const scrollRef = createScrollRef( {
				scrollLeft: -300,
				direction: 'rtl',
			} );
			const { result } = renderHook( () =>
				useScrollIndicators( scrollRef )
			);

			expect( result.current.canScrollLeft ).toBe( false );
			expect( result.current.canScrollRight ).toBe( true );
		} );
	} );
} );
