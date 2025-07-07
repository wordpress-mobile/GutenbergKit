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

// Rely upon promises rather than async/await to avoid timeouts caused by
// circular dependencies. Addressing the circular dependencies is quite
// challenging due to Vite's preload helpers and bugs in `manualChunks`
// configuration.
//
// See:
// - https://github.com/vitejs/vite/issues/18551
// - https://github.com/vitejs/vite/issues/13952
// - https://github.com/vitejs/vite/issues/5189#issuecomment-2175410148
awaitGBKitGlobal()
	.then( initializeApiAndLocale )
	.then( importEditor )
	.then( initializeEditor )
	.catch( handleError );

function initializeApiAndLocale() {
	initializeApiFetch();
	return configureLocale();
}

function importEditor() {
	return import( './utils/editor' );
}

function initializeEditor( editorModule ) {
	const { initializeEditor: _initializeEditor } = editorModule;
	_initializeEditor();
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
