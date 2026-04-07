/**
 * External dependencies
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook } from '@testing-library/react';

/**
 * Internal dependencies
 */
import { useHostBridge } from '../use-host-bridge';
import { getBlockType } from '@wordpress/blocks';

const mockGetEditedPostAttribute = vi.fn();
const mockGetEditedPostContent = vi.fn();
const mockGetSelectedBlockClientId = vi.fn();
const mockGetBlock = vi.fn();
const mockGetSelectionStart = vi.fn();
const mockGetSelectionEnd = vi.fn();

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
	useSelect: ( store ) => {
		if ( store?.name === 'core/editor' ) {
			return {
				getEditedPostAttribute: mockGetEditedPostAttribute,
				getEditedPostContent: mockGetEditedPostContent,
			};
		}
		// block-editor store selectors
		return {
			getSelectedBlockClientId: mockGetSelectedBlockClientId,
			getBlock: mockGetBlock,
			getSelectionStart: mockGetSelectionStart,
			getSelectionEnd: mockGetSelectionEnd,
		};
	},
	useDispatch: vi.fn( () => dispatchMocks ),
} ) );
vi.mock( '@wordpress/core-data' );
vi.mock( '@wordpress/editor' );
vi.mock( '@wordpress/notices' );
vi.mock( '@wordpress/blocks' );
vi.mock( '@wordpress/rich-text', () => ( {
	create: vi.fn( ( { html } ) => ( {
		text: html,
		formats: [],
		replacements: [],
		start: 0,
		end: html.length,
	} ) ),
	insert: vi.fn( ( value, text ) => ( {
		text: value.text + text,
		formats: [],
		replacements: [],
		start: 0,
		end: value.text.length + text.length,
	} ) ),
	toHTMLString: vi.fn( ( { value } ) => value.text ),
} ) );
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

	it( 'getContent returns normalized content string', () => {
		mockGetEditedPostAttribute.mockReturnValue( 'Title' );
		mockGetEditedPostContent.mockReturnValue( {
			raw: '<!-- wp:paragraph -->\n<p>Hello</p>\n<!-- /wp:paragraph -->',
			rendered: '<p>Hello</p>',
		} );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		const result = window.editor.getContent();
		expect( typeof result ).toBe( 'string' );
		expect( result ).toBe(
			'<!-- wp:paragraph -->\n<p>Hello</p>\n<!-- /wp:paragraph -->'
		);
	} );

	it( 'getTitleAndContent returns empty strings when data store returns null', () => {
		mockGetEditedPostAttribute.mockReturnValue( null );
		mockGetEditedPostContent.mockReturnValue( null );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		const result = window.editor.getTitleAndContent();
		expect( result.title ).toBe( '' );
		expect( result.content ).toBe( '' );
	} );

	it( 'getTitleAndContent returns empty strings when data store returns undefined', () => {
		mockGetEditedPostAttribute.mockReturnValue( undefined );
		mockGetEditedPostContent.mockReturnValue( undefined );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		const result = window.editor.getTitleAndContent();
		expect( result.title ).toBe( '' );
		expect( result.content ).toBe( '' );
	} );

	it( 'getTitleAndContent returns empty string for object with raw: null', () => {
		mockGetEditedPostAttribute.mockReturnValue( { raw: null } );
		mockGetEditedPostContent.mockReturnValue( {
			raw: undefined,
		} );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		const result = window.editor.getTitleAndContent();
		expect( result.title ).toBe( '' );
		expect( result.content ).toBe( '' );
	} );

	it( 'getTitleAndContent returns empty string for arrays', () => {
		mockGetEditedPostAttribute.mockReturnValue( [ 'unexpected' ] );
		mockGetEditedPostContent.mockReturnValue( [] );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		const result = window.editor.getTitleAndContent();
		expect( result.title ).toBe( '' );
		expect( result.content ).toBe( '' );
	} );

	it( 'getTitleAndContent coerces non-string primitives to strings', () => {
		mockGetEditedPostAttribute.mockReturnValue( 42 );
		mockGetEditedPostContent.mockReturnValue( false );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		const result = window.editor.getTitleAndContent();
		expect( result.title ).toBe( '42' );
		expect( result.content ).toBe( 'false' );
	} );

	it( 'getTitleAndContent reports changed correctly with object values', () => {
		mockGetEditedPostAttribute.mockReturnValue( {
			raw: 'Changed Title',
			rendered: '<b>Changed Title</b>',
		} );
		mockGetEditedPostContent.mockReturnValue( '' );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		const first = window.editor.getTitleAndContent();
		expect( first.changed ).toBe( true );
		expect( first.title ).toBe( 'Changed Title' );

		const second = window.editor.getTitleAndContent();
		expect( second.changed ).toBe( false );
	} );

	it( 'getTitleAndContent reports changed: false when values match initial state', () => {
		mockGetEditedPostAttribute.mockReturnValue( '' );
		mockGetEditedPostContent.mockReturnValue( '' );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		const result = window.editor.getTitleAndContent();
		expect( result.changed ).toBe( false );
	} );

	it( 'appendTextAtCursor normalizes object-shaped block content', () => {
		mockGetSelectedBlockClientId.mockReturnValue( 'block-1' );
		mockGetBlock.mockReturnValue( {
			name: 'core/paragraph',
			clientId: 'block-1',
			attributes: {
				content: {
					raw: '<p>Existing</p>',
					rendered: '<p>Existing</p>',
				},
			},
		} );
		getBlockType.mockReturnValue( {
			attributes: { content: { type: 'string' } },
		} );
		mockGetSelectionStart.mockReturnValue( {
			clientId: 'block-1',
			attributeKey: 'content',
			offset: 8,
		} );
		mockGetSelectionEnd.mockReturnValue( {
			clientId: 'block-1',
			attributeKey: 'content',
			offset: 8,
		} );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		const result = window.editor.appendTextAtCursor( ' appended' );

		expect( result ).toBe( true );
		expect( dispatchMocks.updateBlock ).toHaveBeenCalledWith( 'block-1', {
			attributes: expect.objectContaining( {
				content: expect.any( String ),
			} ),
		} );
	} );

	it( 'appendTextAtCursor works with plain string block content', () => {
		mockGetSelectedBlockClientId.mockReturnValue( 'block-1' );
		mockGetBlock.mockReturnValue( {
			name: 'core/paragraph',
			clientId: 'block-1',
			attributes: { content: 'Hello' },
		} );
		getBlockType.mockReturnValue( {
			attributes: { content: { type: 'string' } },
		} );
		mockGetSelectionStart.mockReturnValue( {
			clientId: 'block-1',
			attributeKey: 'content',
			offset: 5,
		} );
		mockGetSelectionEnd.mockReturnValue( {
			clientId: 'block-1',
			attributeKey: 'content',
			offset: 5,
		} );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		const result = window.editor.appendTextAtCursor( ' World' );

		expect( result ).toBe( true );
		expect( dispatchMocks.updateBlock ).toHaveBeenCalledWith( 'block-1', {
			attributes: expect.objectContaining( {
				content: expect.any( String ),
			} ),
		} );
	} );

	it( 'appendTextAtCursor preserves existing content when block attribute is a RichTextData object', () => {
		const existingContent = 'Existing block content @';
		const richTextData = {
			toString: () => existingContent,
			valueOf: () => existingContent,
			toHTMLString: () => existingContent,
		};

		mockGetSelectedBlockClientId.mockReturnValue( 'block-1' );
		mockGetBlock.mockReturnValue( {
			name: 'core/paragraph',
			clientId: 'block-1',
			attributes: { content: richTextData },
		} );
		getBlockType.mockReturnValue( {
			attributes: { content: { type: 'string' } },
		} );
		mockGetSelectionStart.mockReturnValue( {
			clientId: 'block-1',
			attributeKey: 'content',
			offset: existingContent.length,
		} );
		mockGetSelectionEnd.mockReturnValue( {
			clientId: 'block-1',
			attributeKey: 'content',
			offset: existingContent.length,
		} );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		window.editor.appendTextAtCursor( 'username ' );

		// The block should contain the original content plus the
		// appended text — not just the appended text alone.
		expect( mockUpdateBlock ).toHaveBeenCalledWith( 'block-1', {
			attributes: expect.objectContaining( {
				content: 'Existing block content @username ',
			} ),
		} );
	} );

	it( 'appendTextAtCursor returns false when no block is selected', () => {
		mockGetSelectedBlockClientId.mockReturnValue( null );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		expect( window.editor.appendTextAtCursor( 'text' ) ).toBe( false );
	} );

	it( 'appendTextAtCursor returns false for blocks without content attribute', () => {
		mockGetSelectedBlockClientId.mockReturnValue( 'block-1' );
		mockGetBlock.mockReturnValue( {
			name: 'core/image',
			clientId: 'block-1',
			attributes: { url: 'test.jpg' },
		} );
		getBlockType.mockReturnValue( {
			attributes: { url: { type: 'string' } },
		} );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		expect( window.editor.appendTextAtCursor( 'text' ) ).toBe( false );
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
