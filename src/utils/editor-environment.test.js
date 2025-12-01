/**
 * External dependencies
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';

/**
 * Internal dependencies
 */
import { setUpEditorEnvironment } from './editor-environment';
import { awaitGBKitGlobal, getGBKit, editorLoaded } from './bridge.js';
import { loadEditorAssets } from './editor-loader.js';
import EditorLoadError from '../components/editor-load-error/index.jsx';
import { error } from './logger.js';
import { initializeVideoPressAjaxBridge } from './videopress-bridge.js';
import { initializeWordPressGlobals } from './wordpress-globals.js';
import { configureLocale } from './localization.js';
import { configureApiFetch } from './api-fetch.js';
import { initializeEditor } from './editor.jsx';

vi.mock( './bridge.js' );
vi.mock( './logger.js' );
vi.mock( './editor-styles.js' );
vi.mock( './videopress-bridge.js' );

vi.mock( './wordpress-globals.js', () => ( {
	initializeWordPressGlobals: vi.fn(),
} ) );

vi.mock( '../components/editor-load-error/index.jsx', () => ( {
	default: vi.fn(),
} ) );

vi.mock( './editor-loader.js', () => ( {
	loadEditorAssets: vi.fn(),
} ) );

vi.mock( './localization.js', () => ( {
	configureLocale: vi.fn(),
} ) );

vi.mock( './api-fetch.js', () => ( {
	configureApiFetch: vi.fn(),
} ) );

vi.mock( './editor.jsx', () => ( {
	initializeEditor: vi.fn(),
} ) );

describe( 'setUpEditorEnvironment', () => {
	beforeEach( () => {
		vi.clearAllMocks();

		awaitGBKitGlobal.mockResolvedValue( undefined );
		getGBKit.mockReturnValue( { plugins: false } );
		configureLocale.mockResolvedValue( undefined );
		initializeWordPressGlobals.mockImplementation( () => {} );
		configureApiFetch.mockImplementation( () => {} );
		initializeVideoPressAjaxBridge.mockImplementation( () => {} );
		initializeEditor.mockImplementation( () => {} );
		EditorLoadError.mockReturnValue( '<div>Error</div>' );
		loadEditorAssets.mockResolvedValue( {
			allowedBlockTypes: [ 'core/paragraph' ],
		} );
	} );

	it( 'executes initialization sequence in correct order', async () => {
		const callOrder = [];

		awaitGBKitGlobal.mockImplementation( () => {
			callOrder.push( 'awaitGBKitGlobal' );
			return Promise.resolve();
		} );

		configureLocale.mockImplementation( () => {
			callOrder.push( 'configureLocale' );
			return Promise.resolve();
		} );

		initializeWordPressGlobals.mockImplementation( () => {
			callOrder.push( 'loadRemainingGlobals' );
		} );

		configureApiFetch.mockImplementation( () => {
			callOrder.push( 'configureApiFetch' );
		} );

		initializeVideoPressAjaxBridge.mockImplementation( () => {
			callOrder.push( 'initializeVideoPress' );
		} );

		initializeEditor.mockImplementation( () => {
			callOrder.push( 'initializeEditor' );
		} );

		await setUpEditorEnvironment();

		expect( callOrder ).toEqual( [
			'awaitGBKitGlobal',
			'configureLocale',
			'loadRemainingGlobals',
			'configureApiFetch',
			'initializeVideoPress',
			'initializeEditor',
		] );
	} );

	it( 'loads plugins when plugins enabled', async () => {
		getGBKit.mockReturnValue( { plugins: true } );

		const allowedTypes = [ 'core/paragraph', 'core/heading', 'core/image' ];
		loadEditorAssets.mockResolvedValue( {
			allowedBlockTypes: allowedTypes,
		} );

		await setUpEditorEnvironment();

		expect( loadEditorAssets ).toHaveBeenCalledTimes( 1 );
	} );

	it( 'skips plugin loading when plugins configuration is disabled', async () => {
		getGBKit.mockReturnValue( { plugins: false } );

		await setUpEditorEnvironment();

		expect( loadEditorAssets ).not.toHaveBeenCalled();
	} );

	it( 'skips plugin loading when plugins configuration is undefined', async () => {
		getGBKit.mockReturnValue( {} );

		await setUpEditorEnvironment();

		expect( loadEditorAssets ).not.toHaveBeenCalled();
	} );

	it( 'handles errors during initialization', async () => {
		const testError = new Error( 'Initialization failed' );
		awaitGBKitGlobal.mockRejectedValue( testError );

		await setUpEditorEnvironment();

		expect( error ).toHaveBeenCalledWith(
			'Error initializing editor',
			testError
		);
		expect( EditorLoadError ).toHaveBeenCalledWith( {
			error: testError,
		} );
		expect( document.body.innerHTML ).toBe( '<div>Error</div>' );
		expect( editorLoaded ).toHaveBeenCalledTimes( 1 );
	} );

	it( 'handles errors during locale configuration', async () => {
		const testError = new Error( 'Locale configuration failed' );
		configureLocale.mockRejectedValue( testError );

		await setUpEditorEnvironment();

		expect( error ).toHaveBeenCalledWith(
			'Error initializing editor',
			testError
		);
		expect( editorLoaded ).toHaveBeenCalledTimes( 1 );
	} );

	it( 'handles errors during editor initialization', async () => {
		const testError = new Error( 'Editor initialization failed' );
		initializeEditor.mockImplementation( () => {
			throw testError;
		} );

		await setUpEditorEnvironment();

		expect( error ).toHaveBeenCalledWith(
			'Error initializing editor',
			testError
		);
		expect( editorLoaded ).toHaveBeenCalledTimes( 1 );
	} );

	it( 'handles errors during plugin loading', async () => {
		getGBKit.mockReturnValue( { plugins: true } );

		const testError = new Error( 'Plugin loading failed' );
		initializeEditor.mockImplementation( () => {
			throw testError;
		} );

		await setUpEditorEnvironment();

		expect( error ).toHaveBeenCalledWith(
			'Error initializing editor',
			testError
		);
		expect( editorLoaded ).toHaveBeenCalledTimes( 1 );
	} );

	it( 'returns a promise that resolves when initialization completes', async () => {
		const result = setUpEditorEnvironment();

		expect( result ).toBeInstanceOf( Promise );
		await expect( result ).resolves.toBeUndefined();
	} );
} );
