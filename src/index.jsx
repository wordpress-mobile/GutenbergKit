/**
 * WordPress dependencies
 */
import { createRoot, StrictMode } from '@wordpress/element';
import { dispatch } from '@wordpress/data';
import { store as editorStore } from '@wordpress/editor';
import { store as preferencesStore } from '@wordpress/preferences';
import { registerCoreBlocks } from '@wordpress/block-library';

/**
 * Internal dependencies
 */
import { initializeApiFetch } from './utils/api-fetch';
import { awaitGBKitGlobal, editorLoaded } from './utils/bridge';
import { configureLocale } from './utils/localization';
import './index.scss';
import EditorLoadError from './components/editor-load-error';
import { error } from './utils/logger';

try {
	await awaitGBKitGlobal();
	initializeApiFetch();
	await configureLocale();

	// Postpone importing `@wordpress` packages until after setting the locale
	const { initializeEditor } = await import( './utils/editor' );
	initializeEditor( {
		StrictMode,
		createRoot,
		dispatch,
		editorStore,
		preferencesStore,
		registerCoreBlocks,
	} );
} catch ( err ) {
	error( 'Error initializing editor', err );
	const root = document.getElementById( 'root' );
	createRoot( root ).render(
		<StrictMode>
			<EditorLoadError error={ err } />
		</StrictMode>
	);
	editorLoaded();
}
