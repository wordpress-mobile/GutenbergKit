/**
 * External dependencies
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render } from '@testing-library/react';

/**
 * WordPress dependencies
 */
import { Component } from '@wordpress/element';
import { doAction, removeAction } from '@wordpress/hooks';

/**
 * Internal dependencies
 */
import { reportEditorCrashesToHost } from './editor-crash-reporting';
import { editorUnavailable, logException } from './bridge';

vi.mock( './bridge', () => ( {
	editorUnavailable: vi.fn(),
	logException: vi.fn(),
} ) );

vi.mock( './logger', () => ( {
	error: vi.fn(),
} ) );

// Mirrors the lifecycle of `@wordpress/editor`'s `ErrorBoundary`, which cannot
// be imported under Vitest.
class ErrorBoundary extends Component {
	state = { error: null };

	static getDerivedStateFromError( error ) {
		return { error };
	}

	componentDidCatch( error ) {
		doAction( 'editor.ErrorBoundary.errorLogged', error );
	}

	render() {
		return this.state.error ? null : this.props.children;
	}
}

describe( 'reportEditorCrashesToHost', () => {
	beforeEach( () => {
		vi.clearAllMocks();
	} );

	afterEach( () => {
		vi.restoreAllMocks();
		removeAction( 'editor.ErrorBoundary.errorLogged', 'GutenbergKit' );
	} );

	it( 'reports a caught editor error to the host', () => {
		reportEditorCrashesToHost();

		const error = new Error( 'Boom' );
		doAction( 'editor.ErrorBoundary.errorLogged', error );

		expect( logException ).toHaveBeenCalledWith( error, {
			isHandled: true,
			handledBy: 'editor.ErrorBoundary.errorLogged',
		} );
	} );

	it( 'notifies the host that the editor is no longer usable', () => {
		reportEditorCrashesToHost();

		doAction( 'editor.ErrorBoundary.errorLogged', new Error( 'Boom' ) );

		expect( editorUnavailable ).toHaveBeenCalledTimes( 1 );
	} );

	it( 'reports a crash thrown during the first render', () => {
		// Silence React's development-mode reporting of the caught error.
		vi.spyOn( console, 'error' ).mockImplementation( () => {} );
		const suppressWindowError = ( event ) => event.preventDefault();
		window.addEventListener( 'error', suppressWindowError );

		function CrashOnRender() {
			throw new Error( 'Boom' );
		}

		reportEditorCrashesToHost();

		try {
			render(
				<ErrorBoundary>
					<CrashOnRender />
				</ErrorBoundary>
			);
		} finally {
			window.removeEventListener( 'error', suppressWindowError );
		}

		expect( editorUnavailable ).toHaveBeenCalledTimes( 1 );
	} );

	it( 'registers its listener once', () => {
		reportEditorCrashesToHost();
		reportEditorCrashesToHost();

		doAction( 'editor.ErrorBoundary.errorLogged', new Error( 'Boom' ) );

		expect( editorUnavailable ).toHaveBeenCalledTimes( 1 );
	} );

	it( 'notifies the host even when logging the crash fails', () => {
		logException.mockImplementationOnce( () => {
			throw new Error( 'Logging failed' );
		} );
		reportEditorCrashesToHost();

		doAction( 'editor.ErrorBoundary.errorLogged', new Error( 'Boom' ) );

		expect( editorUnavailable ).toHaveBeenCalledTimes( 1 );
	} );
} );
