import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook } from '@testing-library/react';
import { useSyncSaveAvailability } from '../use-sync-save-availability';
import { onEditorSaveAvailabilityChanged } from '../../../utils/bridge';

let editorState;

vi.mock( '@wordpress/data', () => ( {
	useSelect: ( mapSelect ) =>
		mapSelect( () => ( {
			__unstableIsEditorReady: () => editorState.isReady,
			isEditedPostSaveable: () => editorState.isSaveable,
			isPostSavingLocked: () => editorState.isSavingLocked,
		} ) ),
} ) );

vi.mock( '@wordpress/editor', () => ( { store: {} } ) );

vi.mock( '../../../utils/bridge', () => ( {
	onEditorSaveAvailabilityChanged: vi.fn(),
} ) );

describe( 'useSyncSaveAvailability', () => {
	beforeEach( () => {
		vi.clearAllMocks();
		editorState = {
			isReady: true,
			isSaveable: true,
			isSavingLocked: false,
		};
	} );

	it( 'reports the initial availability once the editor is ready', () => {
		editorState.isReady = false;
		const { rerender } = renderHook( () => useSyncSaveAvailability() );

		expect( onEditorSaveAvailabilityChanged ).not.toHaveBeenCalled();

		editorState.isReady = true;
		rerender();

		expect( onEditorSaveAvailabilityChanged ).toHaveBeenCalledTimes( 1 );
		expect( onEditorSaveAvailabilityChanged ).toHaveBeenCalledWith(
			true,
			false
		);
	} );

	it( 'reports each change once', () => {
		const { rerender } = renderHook( () => useSyncSaveAvailability() );
		vi.clearAllMocks();

		editorState.isSavingLocked = true;
		rerender();
		rerender();

		expect( onEditorSaveAvailabilityChanged ).toHaveBeenCalledTimes( 1 );
		expect( onEditorSaveAvailabilityChanged ).toHaveBeenCalledWith(
			true,
			true
		);

		editorState.isSaveable = false;
		rerender();

		expect( onEditorSaveAvailabilityChanged ).toHaveBeenCalledTimes( 2 );
		expect( onEditorSaveAvailabilityChanged ).toHaveBeenLastCalledWith(
			false,
			true
		);
	} );

	it( 'does not report a state reverting to the last reported one twice', () => {
		const { rerender } = renderHook( () => useSyncSaveAvailability() );

		editorState.isReady = false;
		rerender();
		editorState.isReady = true;
		rerender();

		expect( onEditorSaveAvailabilityChanged ).toHaveBeenCalledTimes( 1 );
	} );

	it( 'stops reporting after unmounting', () => {
		const { unmount } = renderHook( () => useSyncSaveAvailability() );
		vi.clearAllMocks();

		unmount();

		expect( onEditorSaveAvailabilityChanged ).not.toHaveBeenCalled();
	} );
} );
