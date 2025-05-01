/**
 * WordPress dependencies
 */
import { createRoot, StrictMode } from '@wordpress/element';
import { dispatch } from '@wordpress/data';
import { store as editorStore } from '@wordpress/editor';
import { store as preferencesStore } from '@wordpress/preferences';
import defaultEditorStyles from '@wordpress/block-editor/build-style/default-editor-styles.css?inline';
import { registerCoreBlocks } from '@wordpress/block-library';

/**
 * Internal dependencies
 */
import { initializeApiFetch } from './utils/api-fetch-setup';
import { getGBKit, getPost, waitForGBKit, editorLoaded } from './utils/bridge';
import { configureLocale } from './utils/localization';
import Layout from './components/layout';
import './index.scss';
import EditorLoadError from './components/editor-load-error';

try {
	await waitForGBKit();
	initializeApiFetch();
	await configureLocale();
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

/**
 * Configure editor settings and styles, and render the editor.
 */
function initializeEditor() {
	const { themeStyles, hideTitle, editorSettings } = getGBKit();

	const settings = editorSettings || {
		defaultEditorStyles: [ { css: defaultEditorStyles } ],
	};
	dispatch( editorStore ).updateEditorSettings( settings );

	const preferenceDispatch = dispatch( preferencesStore );
	preferenceDispatch.setDefaults( 'core', {
		fixedToolbar: true,
	} );
	preferenceDispatch.setDefaults( 'core/edit-post', {
		themeStyles,
	} );

	registerCoreBlocks();
	const post = getPost();

	createRoot( document.getElementById( 'root' ) ).render(
		<StrictMode>
			<Layout post={ post } hideTitle={ hideTitle } />
		</StrictMode>
	);
}
