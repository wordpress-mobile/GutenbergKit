/**
 * Internal dependencies
 */
import Layout from '../components/layout';
import { createRoot, StrictMode } from '@wordpress/element';
import { dispatch } from '@wordpress/data';
import { store as editorStore } from '@wordpress/editor';
import { store as preferencesStore } from '@wordpress/preferences';
import { registerCoreBlocks } from '@wordpress/block-library';
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

	// Seed core-data with the post's entity config and record before rendering,
	// so `<EditorProvider>`'s resolvers short-circuit instead of refetching.
	primePostEntity( post );

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
