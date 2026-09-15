/**
 * External dependencies
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen } from '@testing-library/react';

/**
 * WordPress dependencies
 */
import { Component } from '@wordpress/element';

/**
 * Internal dependencies
 */
import EditorErrorBoundary from '.';
import { editorUnavailable, logException } from '../../utils/bridge';

vi.mock( '../../utils/bridge', () => ( {
	editorUnavailable: vi.fn(),
	logException: vi.fn(),
} ) );

vi.mock( '../../utils/logger', () => ( {
	error: vi.fn(),
} ) );

describe( 'EditorErrorBoundary', () => {
	beforeEach( () => {
		vi.clearAllMocks();
		// Silence React's development-mode reporting of caught errors.
		vi.spyOn( console, 'error' ).mockImplementation( () => {} );
		window.addEventListener( 'error', preventDefault );
	} );

	afterEach( () => {
		window.removeEventListener( 'error', preventDefault );
		vi.restoreAllMocks();
	} );

	it( 'renders the editor while it works', () => {
		render(
			<EditorErrorBoundary>
				<p>Editor</p>
			</EditorErrorBoundary>
		);

		expect( screen.getByText( 'Editor' ) ).toBeInTheDocument();
		expect( editorUnavailable ).not.toHaveBeenCalled();
	} );

	it( 'replaces a crashed editor with an error message', () => {
		render(
			<EditorErrorBoundary>
				<CrashOnRender />
			</EditorErrorBoundary>
		);

		expect(
			screen.getByText(
				'The editor has encountered an unexpected error.'
			)
		).toBeInTheDocument();
	} );

	it( 'logs the crash to the host', () => {
		render(
			<EditorErrorBoundary>
				<CrashOnRender />
			</EditorErrorBoundary>
		);

		expect( logException ).toHaveBeenCalledWith( expect.any( Error ), {
			context: { componentStack: expect.any( String ) },
			isHandled: true,
			handledBy: 'EditorErrorBoundary',
		} );
	} );

	it( 'notifies the host that the editor is no longer usable', () => {
		render(
			<EditorErrorBoundary>
				<CrashOnRender />
			</EditorErrorBoundary>
		);

		expect( editorUnavailable ).toHaveBeenCalledTimes( 1 );
	} );

	it( 'notifies the host even when logging the crash fails', () => {
		logException.mockImplementationOnce( () => {
			throw new Error( 'Logging failed' );
		} );

		render(
			<EditorErrorBoundary>
				<CrashOnRender />
			</EditorErrorBoundary>
		);

		expect( editorUnavailable ).toHaveBeenCalledTimes( 1 );
	} );

	it( 'does not report an error contained by a nested boundary', () => {
		render(
			<EditorErrorBoundary>
				<NestedBoundary>
					<CrashOnRender />
				</NestedBoundary>
				<p>Editor</p>
			</EditorErrorBoundary>
		);

		expect( screen.getByText( 'Editor' ) ).toBeInTheDocument();
		expect( logException ).not.toHaveBeenCalled();
		expect( editorUnavailable ).not.toHaveBeenCalled();
	} );
} );

function CrashOnRender() {
	throw new Error( 'Boom' );
}

// Stands in for a boundary nested inside the editor, such as a plugin's.
class NestedBoundary extends Component {
	state = { hasError: false };

	static getDerivedStateFromError() {
		return { hasError: true };
	}

	render() {
		return this.state.hasError ? null : this.props.children;
	}
}

function preventDefault( event ) {
	event.preventDefault();
}
