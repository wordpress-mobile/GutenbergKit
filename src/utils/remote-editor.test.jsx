/**
 * External dependencies
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

/**
 * Internal dependencies
 */
import { initializeRemoteEditor } from './remote-editor.jsx';
import { awaitGBKitGlobal } from './bridge';
import { loadEditorAssets } from './editor-loader.js';
import { configureLocale } from './localization';
import { initializeApiFetch } from './api-fetch';
import { initializeEditor } from './editor';
import { initializeVideoPressAjaxBridge } from './videopress-bridge';
import { isDevMode } from './dev-mode';
import { error, warn } from './logger';

vi.mock( './bridge', () => ( {
	awaitGBKitGlobal: vi.fn(),
} ) );

vi.mock( './editor-loader', () => ( {
	loadEditorAssets: vi.fn(),
} ) );

vi.mock( './localization', () => ( {
	configureLocale: vi.fn(),
} ) );

vi.mock( './api-fetch', () => ( {
	initializeApiFetch: vi.fn(),
} ) );

vi.mock( './editor', () => ( {
	initializeEditor: vi.fn(),
} ) );

vi.mock( './videopress-bridge', () => ( {
	initializeVideoPressAjaxBridge: vi.fn(),
} ) );

vi.mock( './dev-mode', () => ( {
	isDevMode: vi.fn(),
} ) );

vi.mock( './logger', () => ( {
	error: vi.fn(),
	warn: vi.fn(),
} ) );

const I18N_PACKAGES = [ 'i18n', 'hooks' ];
const API_FETCH_PACKAGES = [ 'api-fetch', 'url' ];

function arrayEquals( a, b ) {
	return (
		a.length === b.length &&
		a.every( ( value, index ) => value === b[ index ] )
	);
}

describe( 'Remote Editor Loading Sequence', () => {
	let loadSequence;
	let originalLocation;

	beforeEach( () => {
		vi.clearAllMocks();
		loadSequence = [];
		originalLocation = window.location;

		// Mock window.location for redirect testing
		delete window.location;
		window.location = { href: '' };

		awaitGBKitGlobal.mockResolvedValue( {} );

		loadEditorAssets.mockImplementation(
			( { allowedPackages = [], disallowedPackages = [] } = {} ) => {
				loadSequence.push( {
					action: 'loadEditorAssets',
					allowedPackages: [ ...allowedPackages ],
					disallowedPackages: [ ...disallowedPackages ],
				} );
				return Promise.resolve( {
					allowedBlockTypes: [ 'core/paragraph', 'core/heading' ],
				} );
			}
		);

		configureLocale.mockImplementation( () => {
			loadSequence.push( { action: 'configureLocale' } );
			return Promise.resolve();
		} );

		initializeApiFetch.mockImplementation( () => {
			loadSequence.push( { action: 'initializeApiFetch' } );
		} );

		initializeEditor.mockImplementation( () => {
			loadSequence.push( { action: 'initializeEditor' } );
		} );

		initializeVideoPressAjaxBridge.mockImplementation( () => {
			loadSequence.push( { action: 'initializeVideoPressAjaxBridge' } );
		} );

		isDevMode.mockReturnValue( false );
	} );

	afterEach( () => {
		window.location = originalLocation;
	} );

	it( 'should configure locale before loading api-fetch modules', async () => {
		await initializeRemoteEditor();

		const i18nLoadIndex = loadSequence.findIndex(
			( item ) =>
				item.action === 'loadEditorAssets' &&
				arrayEquals( item.allowedPackages, I18N_PACKAGES )
		);
		const localeIndex = loadSequence.findIndex(
			( item ) => item.action === 'configureLocale'
		);
		const apiFetchLoadIndex = loadSequence.findIndex(
			( item ) =>
				item.action === 'loadEditorAssets' &&
				arrayEquals( item.allowedPackages, API_FETCH_PACKAGES )
		);

		expect( i18nLoadIndex ).toBeLessThan( localeIndex );
		expect( localeIndex ).toBeLessThan( apiFetchLoadIndex );
	} );

	it( 'should configure api-fetch before loading remaining modules', async () => {
		await initializeRemoteEditor();

		const apiFetchLoadIndex = loadSequence.findIndex(
			( item ) =>
				item.action === 'loadEditorAssets' &&
				arrayEquals( item.allowedPackages, API_FETCH_PACKAGES )
		);
		const apiFetchInitIndex = loadSequence.findIndex(
			( item ) => item.action === 'initializeApiFetch'
		);
		const remainingLoadIndex = loadSequence.findIndex(
			( item ) =>
				item.action === 'loadEditorAssets' &&
				arrayEquals( item.disallowedPackages, [
					...I18N_PACKAGES,
					...API_FETCH_PACKAGES,
				] )
		);

		expect( apiFetchLoadIndex ).toBeLessThan( apiFetchInitIndex );
		expect( apiFetchInitIndex ).toBeLessThan( remainingLoadIndex );
	} );

	it( 'should exclude strategically loaded modules when loading remaining assets', async () => {
		await initializeRemoteEditor();

		const finalLoad = loadSequence.find(
			( item ) =>
				item.action === 'loadEditorAssets' &&
				item.disallowedPackages.length > 0
		);

		expect( finalLoad ).toBeDefined();
		expect(
			arrayEquals( finalLoad.disallowedPackages, [
				...I18N_PACKAGES,
				...API_FETCH_PACKAGES,
			] )
		);
	} );

	it( 'should maintain correct sequence even with async delays', async () => {
		// Add delays to simulate real network conditions
		loadEditorAssets.mockImplementation(
			( { allowedPackages = [], disallowedPackages = [] } = {} ) => {
				return new Promise( ( resolve ) => {
					setTimeout( () => {
						loadSequence.push( {
							action: 'loadEditorAssets',
							allowedPackages: [ ...allowedPackages ],
							disallowedPackages: [ ...disallowedPackages ],
						} );
						resolve( { allowedBlockTypes: [] } );
					}, Math.random() * 10 );
				} );
			}
		);

		await initializeRemoteEditor();

		const apiFetchInitIndex = loadSequence.findIndex(
			( item ) => item.action === 'initializeApiFetch'
		);
		const remainingLoadIndex = loadSequence.findIndex(
			( item ) =>
				item.action === 'loadEditorAssets' &&
				arrayEquals( item.disallowedPackages, [
					...I18N_PACKAGES,
					...API_FETCH_PACKAGES,
				] )
		);

		expect( apiFetchInitIndex ).toBeLessThan( remainingLoadIndex );
	} );

	it( 'should pass allowedBlockTypes to initializeEditor', async () => {
		const mockAllowedBlockTypes = [
			'core/paragraph',
			'core/heading',
			'core/image',
		];
		loadEditorAssets.mockResolvedValue( {
			allowedBlockTypes: mockAllowedBlockTypes,
		} );

		await initializeRemoteEditor();

		expect( initializeEditor ).toHaveBeenCalledWith( {
			allowedBlockTypes: mockAllowedBlockTypes,
		} );
	} );

	it( 'should handle errors and redirect to local editor in production', async () => {
		awaitGBKitGlobal.mockRejectedValue(
			new Error( 'GBKit not available' )
		);
		isDevMode.mockReturnValue( false );

		await initializeRemoteEditor();

		expect( error ).toHaveBeenCalledWith(
			'Error initializing editor',
			expect.any( Error )
		);
		expect( window.location.href ).toBe(
			'index.html?error=gbkit_global_unavailable'
		);
	} );

	it( 'should not redirect in dev mode when error occurs', async () => {
		awaitGBKitGlobal.mockRejectedValue(
			new Error( 'GBKit not available' )
		);
		isDevMode.mockReturnValue( true );

		await initializeRemoteEditor();

		expect( error ).toHaveBeenCalledWith(
			'Error initializing editor',
			expect.any( Error )
		);
		expect( warn ).toHaveBeenCalledWith(
			'Dev mode disabled automatic redirect to the local editor.'
		);
		expect( window.location.href ).toBe( '' );
	} );

	it( 'should handle errors during api-fetch loading', async () => {
		let callCount = 0;
		loadEditorAssets.mockImplementation( () => {
			callCount++;
			if ( callCount === 2 ) {
				// Fail on api-fetch loading (second call)
				return Promise.reject(
					new Error( 'Failed to load api-fetch' )
				);
			}
			return Promise.resolve( { allowedBlockTypes: [] } );
		} );
		isDevMode.mockReturnValue( false );

		await initializeRemoteEditor();

		expect( error ).toHaveBeenCalledWith(
			'Error initializing editor',
			expect.any( Error )
		);
		expect( window.location.href ).toBe(
			'index.html?error=gbkit_global_unavailable'
		);
	} );

	it( 'should initialize VideoPress bridge before editor', async () => {
		await initializeRemoteEditor();

		const videoPressIndex = loadSequence.findIndex(
			( item ) => item.action === 'initializeVideoPressAjaxBridge'
		);
		const editorIndex = loadSequence.findIndex(
			( item ) => item.action === 'initializeEditor'
		);

		expect( videoPressIndex ).toBeLessThan( editorIndex );
	} );
} );
