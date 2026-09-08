/**
 * External dependencies
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook } from '@testing-library/react';

/**
 * WordPress dependencies
 */
import { doAction } from '@wordpress/hooks';

/**
 * Internal dependencies
 */
import { useHostExceptionLogging } from '../use-host-exception-logging';
import { editorUnavailable, logException } from '../../../utils/bridge';

vi.mock( '../../../utils/bridge', () => ( {
	editorUnavailable: vi.fn(),
	logException: vi.fn(),
} ) );

describe( 'useHostExceptionLogging', () => {
	beforeEach( () => {
		vi.clearAllMocks();
	} );

	it( 'reports a caught editor error to the host', () => {
		renderHook( () => useHostExceptionLogging() );

		const error = new Error( 'Boom' );
		doAction( 'editor.ErrorBoundary.errorLogged', error );

		expect( logException ).toHaveBeenCalledWith( error, {
			isHandled: true,
			handledBy: 'editor.ErrorBoundary.errorLogged',
		} );
	} );

	it( 'notifies the host that the editor is no longer usable', () => {
		renderHook( () => useHostExceptionLogging() );

		doAction( 'editor.ErrorBoundary.errorLogged', new Error( 'Boom' ) );

		expect( editorUnavailable ).toHaveBeenCalledTimes( 1 );
	} );

	it( 'stops reporting once unmounted', () => {
		const { unmount } = renderHook( () => useHostExceptionLogging() );

		unmount();
		doAction( 'editor.ErrorBoundary.errorLogged', new Error( 'Boom' ) );

		expect( logException ).not.toHaveBeenCalled();
		expect( editorUnavailable ).not.toHaveBeenCalled();
	} );
} );
