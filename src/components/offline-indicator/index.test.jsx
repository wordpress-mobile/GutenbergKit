/**
 * External dependencies
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, act } from '@testing-library/react';

/**
 * Internal dependencies
 */
import OfflineIndicator from '.';

vi.mock( '@wordpress/i18n' );

describe( 'OfflineIndicator', () => {
	let originalOnLine;

	beforeEach( () => {
		originalOnLine = navigator.onLine;
	} );

	afterEach( () => {
		Object.defineProperty( navigator, 'onLine', {
			value: originalOnLine,
			writable: true,
			configurable: true,
		} );
	} );

	it( 'does not render when online', () => {
		Object.defineProperty( navigator, 'onLine', {
			value: true,
			configurable: true,
		} );

		const { container } = render( <OfflineIndicator /> );
		expect( container ).toBeEmptyDOMElement();
	} );

	it( 'renders "Working Offline" when navigator.onLine is false', () => {
		Object.defineProperty( navigator, 'onLine', {
			value: false,
			configurable: true,
		} );

		render( <OfflineIndicator /> );
		expect( screen.getByText( 'Working Offline' ) ).toBeInTheDocument();
	} );

	it( 'auto-hides when online event fires', () => {
		Object.defineProperty( navigator, 'onLine', {
			value: false,
			configurable: true,
		} );

		render( <OfflineIndicator /> );
		expect( screen.getByText( 'Working Offline' ) ).toBeInTheDocument();

		act( () => {
			window.dispatchEvent( new Event( 'online' ) );
		} );

		expect(
			screen.queryByText( 'Working Offline' )
		).not.toBeInTheDocument();
	} );

	it( 're-appears when offline event fires', () => {
		Object.defineProperty( navigator, 'onLine', {
			value: true,
			configurable: true,
		} );

		render( <OfflineIndicator /> );
		expect(
			screen.queryByText( 'Working Offline' )
		).not.toBeInTheDocument();

		act( () => {
			window.dispatchEvent( new Event( 'offline' ) );
		} );

		expect( screen.getByText( 'Working Offline' ) ).toBeInTheDocument();
	} );
} );
