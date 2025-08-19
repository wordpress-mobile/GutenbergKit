/**
 * External dependencies
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent, act } from '@testing-library/react';

/**
 * Internal dependencies
 */
import EditorLoadNotice from './editor-load-notice';

vi.mock( '@wordpress/i18n' );
vi.mock( '@wordpress/components' );

describe( 'EditorLoadNotice', () => {
	beforeEach( () => {
		vi.useFakeTimers();
		vi.stubGlobal( 'location', {
			href: 'https://example.com',
		} );
	} );

	afterEach( () => {
		vi.useRealTimers();
		vi.unstubAllGlobals();
	} );

	it( 'renders nothing when no error is present', () => {
		render( <EditorLoadNotice /> );
		expect( screen.queryByTestId( 'mock-notice' ) ).not.toBeInTheDocument();
	} );

	it( 'renders remote editor load error notice', () => {
		vi.stubGlobal( 'location', {
			href: 'https://example.com?error=remote_editor_load_error',
		} );

		render( <EditorLoadNotice /> );

		expect( screen.getByTestId( 'mock-notice' ) ).toBeInTheDocument();
		expect(
			screen.getByText(
				"Oops! We couldn't load your site's editor and plugins. Don't worry, you can use the default editor for now."
			)
		).toBeInTheDocument();
	} );

	it( 'renders global unavailable error notice', () => {
		vi.stubGlobal( 'location', {
			href: 'https://example.com?error=gbkit_global_unavailable',
		} );

		render( <EditorLoadNotice /> );

		expect( screen.getByTestId( 'mock-notice' ) ).toBeInTheDocument();
		expect(
			screen.getByText(
				"Oops! Configuration for your site editor was unavailable. Don't worry, you can use the default editor for now."
			)
		).toBeInTheDocument();
	} );

	it( 'clears notice when clicking Dismiss button', () => {
		vi.stubGlobal( 'location', {
			href: 'https://example.com?error=remote_editor_load_error',
		} );

		render( <EditorLoadNotice /> );

		expect( screen.getByTestId( 'mock-notice' ) ).toBeInTheDocument();

		fireEvent.click( screen.getByText( 'Dismiss' ) );

		expect( screen.queryByTestId( 'mock-notice' ) ).not.toBeInTheDocument();
	} );

	it( 'redirects when clicking Retry button', () => {
		vi.stubGlobal( 'location', {
			href: 'https://example.com?error=remote_editor_load_error',
		} );

		render( <EditorLoadNotice /> );

		fireEvent.click( screen.getByText( 'Retry' ) );

		expect( window.location.href ).toBe( 'remote.html' );
	} );

	it( 'auto-dismisses notice after 20 seconds', () => {
		vi.stubGlobal( 'location', {
			href: 'https://example.com?error=remote_editor_load_error',
		} );

		render( <EditorLoadNotice /> );

		expect( screen.getByTestId( 'mock-notice' ) ).toBeInTheDocument();

		act( () => {
			vi.advanceTimersByTime( 20000 );
		} );

		expect( screen.queryByTestId( 'mock-notice' ) ).not.toBeInTheDocument();
	} );

	it( 'applies custom className to container', () => {
		vi.stubGlobal( 'location', {
			href: 'https://example.com?error=remote_editor_load_error',
		} );

		const { container } = render(
			<EditorLoadNotice className="custom-class" />
		);

		expect( container.firstChild ).toHaveClass( 'custom-class' );
	} );
} );
