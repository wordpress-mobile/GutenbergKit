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
const mockSavePost = vi.fn();
const mockDidPostSaveRequestFail = vi.fn();
const mockGetCurrentPostId = vi.fn();
const mockRemoveNotice = vi.fn();
const mockEditEntityRecord = vi.fn();
const mockGetEditedEntityRecord = vi.fn();
const mockGetLastEntitySaveError = vi.fn();

vi.mock( '@wordpress/data', () => ( {
	useSelect: ( store ) => {
		if ( store?.name === 'core/editor' ) {
			return {
				getEditedPostAttribute: mockGetEditedPostAttribute,
				getEditedPostContent: mockGetEditedPostContent,
				didPostSaveRequestFail: mockDidPostSaveRequestFail,
				getCurrentPostId: mockGetCurrentPostId,
			};
		}
		if ( store?.name === 'core' ) {
			return {
				getEditedEntityRecord: mockGetEditedEntityRecord,
				getLastEntitySaveError: mockGetLastEntitySaveError,
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
		editEntityRecord: mockEditEntityRecord,
		undo: vi.fn(),
		redo: vi.fn(),
		switchEditorMode: vi.fn(),
		savePost: mockSavePost,
		removeNotice: mockRemoveNotice,
		updateBlock: mockUpdateBlock,
		selectionChange: mockSelectionChange,
	} ),
} ) );
vi.mock( '@wordpress/core-data', () => ( {
	store: { name: 'core' },
} ) );
vi.mock( '@wordpress/editor' );
vi.mock( '@wordpress/notices' );
vi.mock( '@wordpress/blocks' );

const mockAddFilter = vi.fn();
const mockRemoveFilter = vi.fn();
vi.mock( '@wordpress/hooks', () => ( {
	addFilter: ( ...args ) => mockAddFilter( ...args ),
	removeFilter: ( ...args ) => mockRemoveFilter( ...args ),
} ) );

const mockHydratePost = vi.fn();
vi.mock( '../../../utils/bridge', () => ( {
	hydratePost: ( ...args ) => mockHydratePost( ...args ),
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
vi.mock( '@wordpress/block-editor' );
vi.mock( '@wordpress/api-fetch', () => ( { default: vi.fn() } ) );

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
		// Default: existing post with positive ID
		mockGetCurrentPostId.mockReturnValue( 1 );
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
		expect( window.editor.switchEditorMode ).toBeTypeOf( 'function' );
		expect( window.editor.dismissTopModal ).toBeTypeOf( 'function' );
		expect( window.editor.focus ).toBeTypeOf( 'function' );
		expect( window.editor.appendTextAtCursor ).toBeTypeOf( 'function' );
		expect( window.editor.savePost ).toBeTypeOf( 'function' );

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

	it( 'registers editor.preSavePost filter on mount', () => {
		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		expect( mockAddFilter ).toHaveBeenCalledWith(
			'editor.preSavePost',
			'GutenbergKit/hydratePost',
			expect.any( Function )
		);
	} );

	it( 'preSavePost filter passes full entity to native and merges result', async () => {
		const currentEntity = {
			id: 1,
			type: 'post',
			title: { raw: 'Hello' },
			categories: [ 1 ],
		};
		const modifiedPost = {
			categories: [ 1, 2 ],
			tags: [ 3 ],
			featured_media: 42,
		};
		mockGetEditedEntityRecord.mockReturnValue( currentEntity );
		mockHydratePost.mockResolvedValue( modifiedPost );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		const filterCallback = mockAddFilter.mock.calls.find(
			( call ) => call[ 0 ] === 'editor.preSavePost'
		)[ 2 ];

		const edits = { id: 1, content: 'World' };
		const result = await filterCallback( edits );

		expect( mockHydratePost ).toHaveBeenCalledWith( currentEntity );
		expect( result ).toEqual( { ...edits, ...modifiedPost } );
	} );

	it( 'preSavePost filter strips meta from hydrated post to avoid type mismatches', async () => {
		const currentEntity = {
			id: 1,
			type: 'post',
			title: { raw: 'Hello' },
			meta: { _jetpack_newsletter_tier_id: 0 },
		};
		const modifiedPost = {
			categories: [ 1, 2 ],
			meta: { _jetpack_newsletter_tier_id: 0 },
		};
		mockGetEditedEntityRecord.mockReturnValue( currentEntity );
		mockHydratePost.mockResolvedValue( modifiedPost );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		const filterCallback = mockAddFilter.mock.calls.find(
			( call ) => call[ 0 ] === 'editor.preSavePost'
		)[ 2 ];

		const edits = { id: 1, content: 'World' };
		const result = await filterCallback( edits );

		expect( result.categories ).toEqual( [ 1, 2 ] );
		expect( result ).not.toHaveProperty( 'meta' );
	} );

	it( 'preSavePost filter returns edits unchanged when native returns null', async () => {
		mockGetEditedEntityRecord.mockReturnValue( defaultPost );
		mockHydratePost.mockResolvedValue( null );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		const filterCallback = mockAddFilter.mock.calls.find(
			( call ) => call[ 0 ] === 'editor.preSavePost'
		)[ 2 ];

		const edits = { id: 1, content: '' };
		const result = await filterCallback( edits );

		expect( result ).toEqual( edits );
	} );

	it( 'preSavePost filter strips id for new posts so Gutenberg sends POST', async () => {
		mockGetEditedEntityRecord.mockReturnValue( defaultPost );
		mockHydratePost.mockResolvedValue( null );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		const filterCallback = mockAddFilter.mock.calls.find(
			( call ) => call[ 0 ] === 'editor.preSavePost'
		)[ 2 ];

		const edits = { id: -1, content: 'Hello' };
		const result = await filterCallback( edits );

		expect( result ).toEqual( { content: 'Hello' } );
		expect( result ).not.toHaveProperty( 'id' );
	} );

	it( 'savePost calls savePost dispatch and suppresses notice', async () => {
		mockGetEditedEntityRecord.mockReturnValue( defaultPost );
		mockSavePost.mockResolvedValue();
		mockDidPostSaveRequestFail.mockReturnValue( false );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		await window.editor.savePost();

		expect( mockSavePost ).toHaveBeenCalledTimes( 1 );
		expect( mockRemoveNotice ).toHaveBeenCalledWith( 'editor-save' );
	} );

	it( 'savePost suppresses notice even when save fails', async () => {
		mockGetEditedEntityRecord.mockReturnValue( defaultPost );
		mockSavePost.mockRejectedValue( new Error( 'Network error' ) );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		await expect( window.editor.savePost() ).rejects.toThrow(
			'Network error'
		);
		expect( mockRemoveNotice ).toHaveBeenCalledWith( 'editor-save' );
	} );

	it( 'savePost throws when Gutenberg reports save failure', async () => {
		mockGetEditedEntityRecord.mockReturnValue( defaultPost );
		mockSavePost.mockResolvedValue();
		mockDidPostSaveRequestFail.mockReturnValue( true );
		mockGetLastEntitySaveError.mockReturnValue( {
			message: 'REST API error',
		} );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		await expect( window.editor.savePost() ).rejects.toThrow(
			'REST API error'
		);
		expect( mockRemoveNotice ).toHaveBeenCalledWith( 'editor-save' );
	} );

	it( 'savePost does not record server ID for existing posts', async () => {
		mockGetCurrentPostId.mockReturnValue( 1 );
		mockGetEditedEntityRecord.mockReturnValue( defaultPost );
		mockSavePost.mockResolvedValue();
		mockDidPostSaveRequestFail.mockReturnValue( false );

		renderHook( () =>
			useHostBridge( defaultPost, editorRef, markBridgeReady )
		);

		mockEditEntityRecord.mockClear();
		await window.editor.savePost();

		// editEntityRecord should not be called to record a server ID
		// (it may be called for other edits, but never with just { id }).
		const idEditCalls = mockEditEntityRecord.mock.calls.filter(
			( args ) =>
				args[ 3 ] &&
				'id' in args[ 3 ] &&
				Object.keys( args[ 3 ] ).length === 1
		);
		expect( idEditCalls ).toHaveLength( 0 );
	} );

	it( 'savePost passes __unstableFetch for new posts and records server ID as edit', async () => {
		const newPost = { ...defaultPost, id: -1 };
		mockGetCurrentPostId.mockReturnValue( -1 );
		mockGetEditedEntityRecord.mockReturnValue( newPost );
		mockDidPostSaveRequestFail.mockReturnValue( false );

		// When savePost is called, invoke the __unstableFetch wrapper
		// to simulate the server returning a real ID.
		mockSavePost.mockImplementation( async ( options ) => {
			if ( options?.__unstableFetch ) {
				await options.__unstableFetch( {
					method: 'POST',
					path: '/wp/v2/posts',
					data: {},
				} );
			}
		} );

		const { default: apiFetch } = await import( '@wordpress/api-fetch' );
		apiFetch.mockResolvedValue( { id: 42, type: 'post' } );

		renderHook( () =>
			useHostBridge( newPost, editorRef, markBridgeReady )
		);

		mockEditEntityRecord.mockClear();
		await window.editor.savePost();

		expect( mockSavePost ).toHaveBeenCalledWith(
			expect.objectContaining( {
				__unstableFetch: expect.any( Function ),
			} )
		);
		// The server-assigned ID is recorded as an edit on the existing
		// entity rather than switching entities with setEditedPost.
		expect( mockEditEntityRecord ).toHaveBeenCalledWith(
			'postType',
			'post',
			-1,
			{ id: 42 }
		);
	} );

	it( 'cleans up window.editor methods and filter on unmount', () => {
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
		expect( window.editor.switchEditorMode ).toBeUndefined();
		expect( window.editor.dismissTopModal ).toBeUndefined();
		expect( window.editor.focus ).toBeUndefined();
		expect( window.editor.appendTextAtCursor ).toBeUndefined();
		expect( window.editor.savePost ).toBeUndefined();
		expect( mockRemoveFilter ).toHaveBeenCalledWith(
			'editor.preSavePost',
			'GutenbergKit/hydratePost'
		);
	} );
} );
