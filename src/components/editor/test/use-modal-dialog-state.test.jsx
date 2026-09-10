/**
 * External dependencies
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook } from '@testing-library/react';

/**
 * Internal dependencies
 */
import { useModalDialogState } from '../use-modal-dialog-state';
import {
	onModalDialogOpened,
	onModalDialogClosed,
} from '../../../utils/bridge';

vi.mock( '../../../utils/bridge', () => ( {
	onModalDialogOpened: vi.fn(),
	onModalDialogClosed: vi.fn(),
} ) );

describe( 'useModalDialogState', () => {
	beforeEach( () => {
		vi.clearAllMocks();
	} );

	it( 'reports the initial closed state', () => {
		renderHook( () => useModalDialogState( false, 'block-inspector' ) );

		expect( onModalDialogClosed ).toHaveBeenCalledWith( 'block-inspector' );
	} );

	it( 'reports the dialog opening and closing once each', () => {
		const { rerender } = renderHook(
			( { isVisible } ) =>
				useModalDialogState( isVisible, 'block-inspector' ),
			{ initialProps: { isVisible: false } }
		);
		vi.clearAllMocks();

		rerender( { isVisible: true } );

		expect( onModalDialogOpened ).toHaveBeenCalledTimes( 1 );
		expect( onModalDialogOpened ).toHaveBeenCalledWith( 'block-inspector' );

		rerender( { isVisible: false } );

		expect( onModalDialogClosed ).toHaveBeenCalledTimes( 1 );
		expect( onModalDialogClosed ).toHaveBeenCalledWith( 'block-inspector' );
	} );

	it( 'reports an open dialog closed when unmounted', () => {
		const { unmount } = renderHook( () =>
			useModalDialogState( true, 'block-inspector' )
		);

		unmount();

		expect( onModalDialogClosed ).toHaveBeenCalledTimes( 1 );
		expect( onModalDialogClosed ).toHaveBeenCalledWith( 'block-inspector' );
	} );

	it( 'does not report a closed dialog again when unmounted', () => {
		const { unmount } = renderHook( () =>
			useModalDialogState( false, 'block-inspector' )
		);
		vi.clearAllMocks();

		unmount();

		expect( onModalDialogClosed ).not.toHaveBeenCalled();
	} );
} );
