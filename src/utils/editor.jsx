import { createRoot, StrictMode } from '@wordpress/element';
import { dispatch, select } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';
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
	await primePostEntity( post );

	// Like core's edit-post, set up the editor before the first render, so that
	// hooks see the post on mount rather than a later change. `EditorProvider`
	// then skips its own setup.
	const record = select( coreStore ).getEntityRecord(
		'postType',
		post.type,
		post.id
	);
	if ( record ) {
		dispatch( editorStore ).setupEditor(
			record,
			{},
			getNewPostTemplate( record )
		);
	}

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

/**
 * Returns the post type's template to apply to a new post, if any.
 *
 * Only empty new posts are auto-drafts (see `getPost`), so a local draft keeps
 * its blocks. Post types without a template have an empty one, which core would
 * still apply as an edit.
 *
 * @param {Object} post The post.
 * @return {Array|undefined} The template, or undefined to leave the post as is.
 */
function getNewPostTemplate( post ) {
	if ( post.status !== 'auto-draft' ) {
		return undefined;
	}

	const template = select( coreStore ).getPostType( post.type )?.template;
	return template?.length ? template : undefined;
}
