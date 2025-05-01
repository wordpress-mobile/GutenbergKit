/**
 * WordPress dependencies
 */
import { createRoot, StrictMode } from '@wordpress/element';

/**
 * Internal dependencies
 */
import { initializeApiFetch } from './utils/api-fetch';
import { waitForGBKit, editorLoaded } from './utils/bridge';
import { configureLocale } from './utils/localization';
import './index.scss';
import EditorLoadError from './components/editor-load-error';

try {
	await waitForGBKit();
	initializeApiFetch();
	await configureLocale();

	// Postpone importing `@wordpress` packages until after setting the locale
	const { initializeEditor } = await import( './utils/editor' );
	initializeEditor();
} catch ( error ) {
	const root = document.getElementById( 'root' );
	createRoot( root ).render(
		<StrictMode>
			<EditorLoadError error={ error } />
		</StrictMode>
	);
	editorLoaded();
}
