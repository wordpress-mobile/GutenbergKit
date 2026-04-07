/**
 * External dependencies
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook } from '@testing-library/react';

/**
 * Internal dependencies
 */
import { useHostBridge } from '../use-host-bridge';

// Hoisted so the `vi.mock` factory below can capture references to the
// same spies the tests assert on. `vi.mock` is hoisted above imports,
// so plain top-level `const`s aren't visible to its factory.
const dispatchMocks = vi.hoisted( () => ( {
	savePost: vi.fn(),
	removeNotice: vi.fn(),
	undo: vi.fn(),
	redo: vi.fn(),
	switchEditorMode: vi.fn(),
	editEntityRecord: vi.fn(),
	updateBlock: vi.fn(),
	selectionChange: vi.fn(),
} ) );

vi.mock( '@wordpress/data', () => ( {
	useDispatch: vi.fn( () => dispatchMocks ),
	useSelect: vi.fn( ( selector ) => {
		if ( typeof selector === 'function' ) {
			return selector( () => ( {} ) );
		}
		return {};
	} ),
} ) );
vi.mock( '@wordpress/core-data' );
vi.mock( '@wordpress/editor' );
vi.mock( '@wordpress/notices' );
vi.mock( '@wordpress/blocks' );
vi.mock( '@wordpress/block-editor' );

const defaultPost = {
	id: 1,
	type: 'post',
	title: { raw: '' },
	content: { raw: '' },
};

describe( 'useHostBridge', () => {
	let editorRef;
	let markBridgeReady;

	beforeEach( () => {
		vi.clearAllMocks();
		editorRef = { current: document.createElement( 'div' ) };
		markBridgeReady = vi.fn();
		// Reset window.editor to initial state (matches the module-level
		// `window.editor = window.editor || {}` in use-host-bridge.js)
		window.editor = {};
	} );

	it( 'assigns window.editor methods and calls markBridgeReady', () => {
		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		// Verify all bridge methods exist
		expect( window.editor.setContent ).toBeTypeOf( 'function' );
		expect( window.editor.setTitle ).toBeTypeOf( 'function' );
		expect( window.editor.getContent ).toBeTypeOf( 'function' );
		expect( window.editor.getTitleAndContent ).toBeTypeOf( 'function' );
		expect( window.editor.undo ).toBeTypeOf( 'function' );
		expect( window.editor.redo ).toBeTypeOf( 'function' );
		expect( window.editor.savePost ).toBeTypeOf( 'function' );
		expect( window.editor.switchEditorMode ).toBeTypeOf( 'function' );
		expect( window.editor.dismissTopModal ).toBeTypeOf( 'function' );
		expect( window.editor.focus ).toBeTypeOf( 'function' );
		expect( window.editor.appendTextAtCursor ).toBeTypeOf( 'function' );

		expect( markBridgeReady ).toHaveBeenCalledTimes( 1 );
	} );

	it( 'cleans up window.editor methods on unmount', () => {
		const { unmount } = renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		expect( window.editor.setContent ).toBeTypeOf( 'function' );

		unmount();

		expect( window.editor.setContent ).toBeUndefined();
		expect( window.editor.setTitle ).toBeUndefined();
		expect( window.editor.getContent ).toBeUndefined();
		expect( window.editor.getTitleAndContent ).toBeUndefined();
		expect( window.editor.undo ).toBeUndefined();
		expect( window.editor.redo ).toBeUndefined();
		expect( window.editor.savePost ).toBeUndefined();
		expect( window.editor.switchEditorMode ).toBeUndefined();
		expect( window.editor.dismissTopModal ).toBeUndefined();
		expect( window.editor.focus ).toBeUndefined();
		expect( window.editor.appendTextAtCursor ).toBeUndefined();
	} );

	describe( 'window.editor.savePost', () => {
		it( 'removes the editor-save snackbar after a successful save', async () => {
			dispatchMocks.savePost.mockResolvedValueOnce( undefined );

			renderHook( () =>
				useHostBridge( defaultPost, editorRef, markBridgeReady )
			);

			await window.editor.savePost();

			expect( dispatchMocks.savePost ).toHaveBeenCalledTimes( 1 );
			expect( dispatchMocks.removeNotice ).toHaveBeenCalledWith(
				'editor-save'
			);
		} );

		it( 'removes the editor-save snackbar even when the save fails', async () => {
			const failure = new Error( 'plugin lifecycle error' );
			dispatchMocks.savePost.mockRejectedValueOnce( failure );

			renderHook( () =>
				useHostBridge( defaultPost, editorRef, markBridgeReady )
			);

			await expect( window.editor.savePost() ).rejects.toThrow( failure );

			expect( dispatchMocks.savePost ).toHaveBeenCalledTimes( 1 );
			expect( dispatchMocks.removeNotice ).toHaveBeenCalledWith(
				'editor-save'
			);
		} );
	} );
} );
