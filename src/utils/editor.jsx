/**
 * WordPress dependencies
 */
import defaultEditorStyles from '@wordpress/block-editor/build-style/default-editor-styles.css?inline';

/**
 * Internal dependencies
 */
import Layout from '../components/layout';
import {
	createRoot as _createRoot,
	StrictMode as _StrictMode,
} from '@wordpress/element';
import { dispatch as _dispatch } from '@wordpress/data';
import { store as _editorStore } from '@wordpress/editor';
import { store as _preferencesStore } from '@wordpress/preferences';
import { registerCoreBlocks as _registerCoreBlocks } from '@wordpress/block-library';
import { getGBKit, getPost } from './bridge';

/**
 * Configure editor settings and styles, and render the editor.
 *
 * Dependency injection is used for various `@wordpress` package functions so
 * that this utility can be used in both the local and remote editor, which
 * rely upon ES modules and global variables, respectively.
 *
 * @param {Object}   wpDependencies                    - WordPress dependencies.
 * @param {Function} wpDependencies.createRoot
 * @param {Function} wpDependencies.StrictMode
 * @param {Function} wpDependencies.dispatch
 * @param {Function} wpDependencies.editorStore
 * @param {Function} wpDependencies.preferencesStore
 * @param {Function} wpDependencies.registerCoreBlocks
 */
export function initializeEditor( {
	createRoot = _createRoot,
	StrictMode = _StrictMode,
	dispatch = _dispatch,
	editorStore = _editorStore,
	preferencesStore = _preferencesStore,
	registerCoreBlocks = _registerCoreBlocks,
} = {} ) {
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
