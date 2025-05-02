/**
 * WordPress dependencies
 */
import { getBlockTypes, unregisterBlockType } from '@wordpress/blocks';
import defaultEditorStyles from '@wordpress/block-editor/build-style/default-editor-styles.css?inline';

/**
 * Internal dependencies
 */
import Layout from '../components/layout';
import { getGBKit, getPost } from './bridge';
import { debug } from './logger';

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
	createRoot,
	StrictMode,
	dispatch,
	editorStore,
	preferencesStore,
	registerCoreBlocks,
} ) {
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

/**
 * Unregister blocks that are disallowed.
 *
 * @param {Array} allowedBlockTypes The list of allowed block types.
 */
export function unregisterDisallowedBlocks( allowedBlockTypes ) {
	if ( ! allowedBlockTypes ) {
		return;
	}

	const unregisteredBlocks = [];
	getBlockTypes().forEach( ( block ) => {
		if ( ! allowedBlockTypes.includes( block.name ) ) {
			unregisterBlockType( block.name );
			unregisteredBlocks.push( block.name );
		}
	} );

	debug( 'Blocks unregistered:', unregisteredBlocks );
}
