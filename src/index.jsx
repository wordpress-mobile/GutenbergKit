/**
 * WordPress dependencies
 */
import { createRoot, StrictMode } from '@wordpress/element';
// Default styles that are needed for the editor.
import '@wordpress/components/build-style/style.css';
import '@wordpress/block-editor/build-style/style.css';
// Default styles that are needed for the core blocks.
import '@wordpress/block-library/build-style/style.css';
import '@wordpress/block-library/build-style/editor.css';
import '@wordpress/block-library/build-style/theme.css';
import '@wordpress/format-library/build-style/style.css';
import '@wordpress/block-editor/build-style/content.css';
import '@wordpress/editor/build-style/style.css';

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

	// Ensure the correct translation strings are used by postponing the import
	// of `@wordpress` packages until after the locale is set.
	//
	// @TODO: A circular dependency prevents the use of async/await. Ideally, we
	// address the circular dependency using Rollup's `manualChunks`. However, a
	// very specific configuration is necessary to ensure that no circular
	// dependencies are created--includeing from injected Vite helpers.
	//
	// See:
	// - https://github.com/vitejs/vite/issues/18551
	// - https://github.com/vitejs/vite/issues/13952
	// - https://github.com/vitejs/vite/issues/5189#issuecomment-2175410148
	import( './utils/editor' )
		.then( ( { initializeEditor } ) => {
			initializeEditor();
		} )
		.catch( ( err ) => {
			handleError( err );
		} );
} catch ( err ) {
	handleError( err );
}

function handleError( err ) {
	error( 'Error initializing editor', err );
	const root = document.getElementById( 'root' );
	createRoot( root ).render(
		<StrictMode>
			<EditorLoadError error={ err } />
		</StrictMode>
	);
	editorLoaded();
}
