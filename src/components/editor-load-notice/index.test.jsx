/**
 * External dependencies
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent, act } from '@testing-library/react';

/**
 * Internal dependencies
 */
import EditorLoadNotice from '.';

vi.mock( '@wordpress/components' );

describe( 'EditorLoadNotice', () => {
	beforeEach( () => {
		vi.useFakeTimers();
	} );

	afterEach( () => {
		vi.useRealTimers();
	} );

	it( 'renders nothing when no error is present', () => {
		render( <EditorLoadNotice /> );
		expect( screen.queryByTestId( 'mock-notice' ) ).not.toBeInTheDocument();
	} );

	it( 'renders plugin load failed notice', () => {
		render( <EditorLoadNotice pluginLoadFailed={ true } /> );

		expect( screen.getByTestId( 'mock-notice' ) ).toBeInTheDocument();
		expect(
			screen.getByText(
				'Loading plugins failed, using default editor configuration.'
			)
		).toBeInTheDocument();
	} );

	it( 'clears notice when clicking Dismiss button', () => {
		render( <EditorLoadNotice pluginLoadFailed={ true } /> );

		expect( screen.getByTestId( 'mock-notice' ) ).toBeInTheDocument();

		fireEvent.click( screen.getByTestId( 'notice-dismiss' ) );

		expect( screen.queryByTestId( 'mock-notice' ) ).not.toBeInTheDocument();
	} );

	it( 'auto-dismisses notice after 20 seconds', () => {
		render( <EditorLoadNotice pluginLoadFailed={ true } /> );

		expect( screen.getByTestId( 'mock-notice' ) ).toBeInTheDocument();

		act( () => {
			vi.advanceTimersByTime( 20000 );
		} );

		expect( screen.queryByTestId( 'mock-notice' ) ).not.toBeInTheDocument();
	} );

	it( 'applies custom className to container', () => {
		const { container } = render(
			<EditorLoadNotice
				pluginLoadFailed={ true }
				className="custom-class"
			/>
		);

		expect( container.firstChild ).toHaveClass( 'custom-class' );
	} );
} );
