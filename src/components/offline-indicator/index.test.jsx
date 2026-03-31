/**
 * External dependencies
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, act } from '@testing-library/react';

/**
 * Internal dependencies
 */
import OfflineIndicator from '.';

vi.mock( '../../utils/bridge', () => ( {
	getGBKit: vi.fn( () => ( {} ) ),
} ) );

describe( 'OfflineIndicator', () => {
	beforeEach( () => {
		// Default: navigator.onLine is true, fetch probe succeeds.
		Object.defineProperty( navigator, 'onLine', {
			value: true,
			configurable: true,
		} );
		vi.stubGlobal(
			'fetch',
			vi.fn( () =>
				Promise.resolve( new Response( null, { status: 200 } ) )
			)
		);
	} );

	afterEach( () => {
		vi.unstubAllGlobals();
		vi.restoreAllMocks();
	} );

	it( 'does not render when navigator.onLine is true and probe succeeds', async () => {
		const { container } = await act( async () =>
			render( <OfflineIndicator /> )
		);
		expect( container ).toBeEmptyDOMElement();
	} );

	it( 'renders immediately when navigator.onLine is false on mount', () => {
		Object.defineProperty( navigator, 'onLine', {
			value: false,
			configurable: true,
		} );

		render( <OfflineIndicator /> );
		expect( screen.getByText( 'Working Offline' ) ).toBeInTheDocument();
	} );

	it( 'renders when navigator.onLine is true on mount but probe fails', async () => {
		vi.stubGlobal(
			'fetch',
			vi.fn( () => Promise.reject( new Error( 'Network error' ) ) )
		);

		await act( async () => render( <OfflineIndicator /> ) );

		expect( screen.getByText( 'Working Offline' ) ).toBeInTheDocument();
	} );

	it( 're-appears when offline event fires', async () => {
		await act( async () => render( <OfflineIndicator /> ) );
		expect(
			screen.queryByText( 'Working Offline' )
		).not.toBeInTheDocument();

		await act( async () => {
			window.dispatchEvent( new Event( 'offline' ) );
		} );

		expect( screen.getByText( 'Working Offline' ) ).toBeInTheDocument();
	} );

	it( 'auto-hides when online event fires and probe succeeds', async () => {
		await act( async () => render( <OfflineIndicator /> ) );

		await act( async () => {
			window.dispatchEvent( new Event( 'offline' ) );
		} );

		expect( screen.getByText( 'Working Offline' ) ).toBeInTheDocument();

		await act( async () => {
			window.dispatchEvent( new Event( 'online' ) );
		} );

		expect(
			screen.queryByText( 'Working Offline' )
		).not.toBeInTheDocument();
	} );

	it( 'remains offline when online event fires but probe fails', async () => {
		vi.stubGlobal(
			'fetch',
			vi.fn( () => Promise.reject( new Error( 'Network error' ) ) )
		);

		await act( async () => render( <OfflineIndicator /> ) );

		await act( async () => {
			window.dispatchEvent( new Event( 'offline' ) );
		} );

		await act( async () => {
			window.dispatchEvent( new Event( 'online' ) );
		} );

		expect( screen.getByText( 'Working Offline' ) ).toBeInTheDocument();
	} );

	it( 'probes the siteApiRoot when available', async () => {
		const { getGBKit } = await import( '../../utils/bridge' );
		getGBKit.mockReturnValue( {
			siteApiRoot: 'https://example.com/wp-json/',
		} );

		await act( async () => render( <OfflineIndicator /> ) );
		await act( async () => {
			window.dispatchEvent( new Event( 'online' ) );
		} );

		expect( fetch ).toHaveBeenCalledWith(
			'https://example.com/wp-json/',
			expect.objectContaining( {
				method: 'HEAD',
				cache: 'no-store',
			} )
		);
	} );

	it( 'falls back to /favicon.ico when siteApiRoot is not configured', async () => {
		const { getGBKit } = await import( '../../utils/bridge' );
		getGBKit.mockReturnValue( {} );

		await act( async () => render( <OfflineIndicator /> ) );
		await act( async () => {
			window.dispatchEvent( new Event( 'online' ) );
		} );

		expect( fetch ).toHaveBeenCalledWith(
			'/favicon.ico',
			expect.objectContaining( {
				method: 'HEAD',
				cache: 'no-store',
			} )
		);
	} );
} );
