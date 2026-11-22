import { createRoot, StrictMode } from '@wordpress/element';
import { dispatch, resolveSelect, select } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';
import { store as editorStore } from '@wordpress/editor';
import { store as preferencesStore } from '@wordpress/preferences';
import { registerCoreBlocks } from '@wordpress/block-library';
import { parse } from '@wordpress/blocks';
import Layout from '../components/layout';
import { unregisterDisallowedBlocks } from './blocks';
import { getGBKit, getPost } from './bridge';
import { getDefaultEditorSettings } from './editor-settings';
import { warn } from './logger';
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
		applyHostEdits( record );
	}

	applyPostTypeTemplateSettings( post.type );

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
 * Applies the changes the host has to the post the server doesn't, as unsaved
 * edits over the saved version the editor opened with.
 *
 * Keeping them out of the saved version means that when core-data later takes
 * in another copy of the post, they stay. They're left out of the undo
 * history, so undo never goes back to the server's version.
 *
 * @param {Object} post The post's saved version.
 * @return {void}
 */
function applyHostEdits( post ) {
	const { postEdits } = getGBKit();
	if ( ! postEdits || Object.keys( postEdits ).length === 0 ) {
		return;
	}

	// The block editor shows the `blocks` edit, which setting up a new post
	// may have made from its template, so the host's content replaces it.
	const edits =
		'content' in postEdits
			? { ...postEdits, blocks: parse( postEdits.content ) }
			: postEdits;
	dispatch( coreStore ).editEntityRecord(
		'postType',
		post.type,
		post.id,
		edits,
		{ undoIgnore: true }
	);
}

/**
 * Returns the post type's template to apply to a new post, if any.
 *
 * Only auto-drafts get the template, as in core. GBK seeds that status only for
 * empty new posts (see `getPost`), so a local draft keeps its blocks. Post types
 * without a template have an empty one, which core would still apply as an edit.
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

/**
 * Adds the post type's template and its lock to the editor settings, as WP
 * Admin does for every post of the type, so the editor enforces a locked
 * template.
 *
 * Only new posts wait for the post type before rendering (see
 * `primePostEntity`), so other posts get the lock once it loads.
 *
 * @param {string} postType The post type.
 * @return {Promise<void>} Resolves once the settings are updated or skipped.
 */
async function applyPostTypeTemplateSettings( postType ) {
	let type;
	try {
		type = await resolveSelect( coreStore ).getPostType( postType );
	} catch ( err ) {
		warn( `Failed to load post type "${ postType }"`, err );
		return;
	}

	if ( ! type?.template?.length ) {
		return;
	}

	dispatch( editorStore ).updateEditorSettings( {
		template: type.template,
		templateLock: type.template_lock || false,
	} );
}
