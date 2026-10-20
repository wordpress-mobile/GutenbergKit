import { createRoot, StrictMode } from '@wordpress/element';
import { dispatch } from '@wordpress/data';
import { store as editorStore } from '@wordpress/editor';
import { store as preferencesStore } from '@wordpress/preferences';
import { registerCoreBlocks } from '@wordpress/block-library';
import Layout from '../components/layout';
import { unregisterDisallowedBlocks } from './blocks';
import { getGBKit, getPost } from './bridge';
import { getDefaultEditorSettings } from './editor-settings';
import { primePostEntity } from './prime-post-entity';

/**
 * Configure editor settings and styles, and render the editor.
 *
 * @param {Object}  [options]
 * @param {Array}   [options.allowedBlockTypes] Array of allowed block types
 * @param {boolean} [options.pluginLoadFailed]  Whether plugin loading failed
 */
export async function initializeEditor( {
	allowedBlockTypes,
	pluginLoadFailed,
} = {} ) {
	const { themeStyles, hideTitle, editorSettings } = getGBKit();

	const settings = editorSettings || getDefaultEditorSettings();
	dispatch( editorStore ).updateEditorSettings( settings );

	const preferenceDispatch = dispatch( preferencesStore );
	preferenceDispatch.setDefaults( 'core', {
		fixedToolbar: true,
	} );
	preferenceDispatch.setDefaults( 'core/edit-post', {
		themeStyles,
	} );

	// Force visual mode on initialization to ensure consistency with native UI,
	// which defaults to visual mode. In the future, we could allow the native
	// host app to configure the initial editor mode.
	preferenceDispatch.set( 'core', 'editorMode', 'visual' );

	registerCoreBlocks();
	unregisterDisallowedBlocks( allowedBlockTypes );

	const post = await getPost();
	const record = await primePostEntity( post );

	// Like core's edit-post, set up the editor before the first render, so that
	// hooks see the post on mount rather than a later change. `EditorProvider`
	// then skips its own setup.
	dispatch( editorStore ).setupEditor( record, {} );

	createRoot( document.getElementById( 'root' ) ).render(
		<StrictMode>
			<Layout
				post={ post }
				hideTitle={ hideTitle }
				pluginLoadFailed={ pluginLoadFailed }
			/>
		</StrictMode>
	);
}
