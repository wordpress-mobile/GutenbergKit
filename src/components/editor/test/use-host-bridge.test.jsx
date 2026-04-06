/**
 * External dependencies
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook } from '@testing-library/react';

/**
 * Internal dependencies
 */
import { useHostBridge } from '../use-host-bridge';

const mockGetEditedPostAttribute = vi.fn();
const mockGetEditedPostContent = vi.fn();

vi.mock( '@wordpress/data', () => ( {
	useSelect: ( store ) => {
		if ( store?.name === 'core/editor' ) {
			return {
				getEditedPostAttribute: mockGetEditedPostAttribute,
				getEditedPostContent: mockGetEditedPostContent,
			};
		}
		// block-editor store selectors
		return {
			getSelectedBlockClientId: vi.fn(),
			getBlock: vi.fn(),
			getSelectionStart: vi.fn(),
			getSelectionEnd: vi.fn(),
		};
	},
	useDispatch: () => ( {
		editEntityRecord: vi.fn(),
		undo: vi.fn(),
		redo: vi.fn(),
		switchEditorMode: vi.fn(),
		updateBlock: vi.fn(),
		selectionChange: vi.fn(),
	} ),
} ) );
vi.mock( '@wordpress/core-data', () => ( {
	store: { name: 'core' },
} ) );
vi.mock( '@wordpress/editor', () => ( {
	store: { name: 'core/editor' },
} ) );
vi.mock( '@wordpress/blocks' );
vi.mock( '@wordpress/block-editor', () => ( {
	store: { name: 'core/block-editor' },
} ) );

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
		expect( window.editor.getTitleAndContent ).toBeTypeOf( 'function' );
		expect( window.editor.undo ).toBeTypeOf( 'function' );
		expect( window.editor.redo ).toBeTypeOf( 'function' );
		expect( window.editor.switchEditorMode ).toBeTypeOf( 'function' );
		expect( window.editor.dismissTopModal ).toBeTypeOf( 'function' );
		expect( window.editor.focus ).toBeTypeOf( 'function' );
		expect( window.editor.appendTextAtCursor ).toBeTypeOf( 'function' );

		expect( markBridgeReady ).toHaveBeenCalledTimes( 1 );
	} );

	it( 'getTitleAndContent returns plain strings when data store returns objects', () => {
		mockGetEditedPostAttribute.mockReturnValue( {
			raw: 'Hello World',
			rendered: '<b>Hello World</b>',
		} );
		mockGetEditedPostContent.mockReturnValue( {
			raw: '<!-- wp:paragraph -->\n<p>Hello</p>\n<!-- /wp:paragraph -->',
			rendered: '<p>Hello</p>',
			protected: false,
		} );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		const result = window.editor.getTitleAndContent();
		expect( result.title ).toBe( 'Hello World' );
		expect( result.content ).toBe(
			'<!-- wp:paragraph -->\n<p>Hello</p>\n<!-- /wp:paragraph -->'
		);
	} );

	it( 'getTitleAndContent passes through plain strings unchanged', () => {
		mockGetEditedPostAttribute.mockReturnValue( 'Plain Title' );
		mockGetEditedPostContent.mockReturnValue( 'Plain Content' );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		const result = window.editor.getTitleAndContent();
		expect( result.title ).toBe( 'Plain Title' );
		expect( result.content ).toBe( 'Plain Content' );
	} );

	it( 'cleans up window.editor methods on unmount', () => {
		const { unmount } = renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		expect( window.editor.setContent ).toBeTypeOf( 'function' );

		unmount();

		expect( window.editor.setContent ).toBeUndefined();
		expect( window.editor.setTitle ).toBeUndefined();
		expect( window.editor.getTitleAndContent ).toBeUndefined();
		expect( window.editor.undo ).toBeUndefined();
		expect( window.editor.redo ).toBeUndefined();
		expect( window.editor.switchEditorMode ).toBeUndefined();
		expect( window.editor.dismissTopModal ).toBeUndefined();
		expect( window.editor.focus ).toBeUndefined();
		expect( window.editor.appendTextAtCursor ).toBeUndefined();
	} );
} );
