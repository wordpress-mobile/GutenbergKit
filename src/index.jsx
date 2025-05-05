/**
 * WordPress dependencies
 */
import { createRoot, StrictMode } from '@wordpress/element';

/**
 * Internal dependencies
 */
import { initializeApiFetch } from './utils/api-fetch';
import { awaitGBKitGlobal, editorLoaded } from './utils/bridge';
import { configureLocale } from './utils/localization';
import './index.scss';
import EditorLoadError from './components/editor-load-error';
import { error } from './utils/logger';
import { loadEditorAssets } from './utils/local-editor';

try {
	await awaitGBKitGlobal();
	initializeApiFetch();
	await configureLocale();

	// Ensure the correct translation strings are used by postponing the import
	// of `@wordpress` packages until after the locale is set.
	const wpDependencies = await loadEditorAssets();
	const { initializeEditor } = await import( './utils/editor' );
	initializeEditor( wpDependencies );
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
