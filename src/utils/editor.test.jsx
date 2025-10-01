/**
 * External dependencies
 */
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { dispatch } from '@wordpress/data';
import { registerCoreBlocks } from '@wordpress/block-library';

/**
 * Internal dependencies
 */
import { initializeEditor } from './editor';
import { getGBKit, getPost } from './bridge';
import { getDefaultEditorSettings } from './editor-settings';
import { unregisterDisallowedBlocks } from './blocks';

vi.mock( '@wordpress/editor', () => ( {
	store: { name: 'core/editor' },
} ) );
vi.mock( '@wordpress/data' );
vi.mock( '@wordpress/preferences' );
vi.mock( '@wordpress/block-library' );
vi.mock( './blocks' );
vi.mock( './bridge' );
vi.mock( './editor-settings' );
vi.mock( '../components/layout', () => ( {
	default: () => null,
} ) );

describe( 'initializeEditor', () => {
	let mockDispatch;
	let mockPreferenceDispatch;
	let mockEditorDispatch;

	beforeEach( () => {
		vi.clearAllMocks();

		mockPreferenceDispatch = {
			setDefaults: vi.fn(),
			set: vi.fn(),
		};

		mockEditorDispatch = {
			updateEditorSettings: vi.fn(),
		};

		mockDispatch = vi.fn( ( store ) => {
			if ( store.name === 'core/preferences' ) {
				return mockPreferenceDispatch;
			}
			if ( store.name === 'core/editor' ) {
				return mockEditorDispatch;
			}
			return {};
		} );

		dispatch.mockImplementation( mockDispatch );

		getGBKit.mockReturnValue( {
			themeStyles: true,
			hideTitle: false,
			editorSettings: null,
		} );
		getPost.mockReturnValue( {
			id: 1,
			type: 'post',
			title: { raw: 'Test Post' },
			content: { raw: '' },
		} );

		getDefaultEditorSettings.mockReturnValue( {} );

		document.body.innerHTML = '<div id="root"></div>';
	} );

	it( 'should force editor mode to visual on initialization', () => {
		initializeEditor();

		expect( mockPreferenceDispatch.set ).toHaveBeenCalledWith(
			'core',
			'editorMode',
			'visual'
		);
	} );

	it( 'should set enable the fixed toolbar', () => {
		initializeEditor();

		expect( mockPreferenceDispatch.setDefaults ).toHaveBeenCalledWith(
			'core',
			expect.objectContaining( {
				fixedToolbar: true,
			} )
		);
	} );

	it( 'should configure the theme styles preference', () => {
		getGBKit.mockReturnValue( {
			themeStyles: false,
			hideTitle: false,
			editorSettings: null,
		} );

		initializeEditor();

		expect( mockPreferenceDispatch.setDefaults ).toHaveBeenCalledWith(
			'core/edit-post',
			expect.objectContaining( {
				themeStyles: false,
			} )
		);
	} );

	it( 'should update editor settings', () => {
		const mockSettings = { setting1: 'value1' };
		getDefaultEditorSettings.mockReturnValue( mockSettings );

		initializeEditor();

		expect( mockEditorDispatch.updateEditorSettings ).toHaveBeenCalledWith(
			mockSettings
		);
	} );

	it( 'should use custom editor settings if provided', () => {
		const customSettings = { custom: 'settings' };
		getGBKit.mockReturnValue( {
			themeStyles: true,
			hideTitle: false,
			editorSettings: customSettings,
		} );

		initializeEditor();

		expect( mockEditorDispatch.updateEditorSettings ).toHaveBeenCalledWith(
			customSettings
		);
	} );

	it( 'should pass allowedBlockTypes to unregisterDisallowedBlocks', () => {
		const allowedBlockTypes = [ 'core/paragraph', 'core/heading' ];

		initializeEditor( { allowedBlockTypes } );

		expect( unregisterDisallowedBlocks ).toHaveBeenCalledWith(
			allowedBlockTypes
		);
	} );

	it( 'should register core blocks', () => {
		initializeEditor();

		expect( registerCoreBlocks ).toHaveBeenCalled();
	} );
} );
