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
const mockUpdateBlock = vi.fn();
const mockSelectionChange = vi.fn();

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
	useDispatch: () => ( {
		editEntityRecord: vi.fn(),
		undo: vi.fn(),
		redo: vi.fn(),
		switchEditorMode: vi.fn(),
		updateBlock: mockUpdateBlock,
		selectionChange: mockSelectionChange,
	} ),
} ) );
vi.mock( '@wordpress/core-data', () => ( {
	store: { name: 'core' },
} ) );
vi.mock( '@wordpress/editor', () => ( {
	store: { name: 'core/editor' },
} ) );
vi.mock( '@wordpress/blocks', () => ( {
	parse: vi.fn( () => [] ),
	serialize: vi.fn( () => '' ),
	getBlockType: vi.fn(),
} ) );
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
		expect( mockUpdateBlock ).toHaveBeenCalledWith( 'block-1', {
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
		expect( mockUpdateBlock ).toHaveBeenCalledWith( 'block-1', {
			attributes: expect.objectContaining( {
				content: expect.any( String ),
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
		expect( window.editor.getTitleAndContent ).toBeUndefined();
		expect( window.editor.undo ).toBeUndefined();
		expect( window.editor.redo ).toBeUndefined();
		expect( window.editor.switchEditorMode ).toBeUndefined();
		expect( window.editor.dismissTopModal ).toBeUndefined();
		expect( window.editor.focus ).toBeUndefined();
		expect( window.editor.appendTextAtCursor ).toBeUndefined();
	} );
} );
