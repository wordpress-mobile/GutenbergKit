/**
 * WordPress dependencies
 */
import { useEffect } from '@wordpress/element';
import { useDispatch } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';
import { store as editorStore } from '@wordpress/editor';
import { getBlockTypes, unregisterBlockType } from '@wordpress/blocks';
import { registerCoreBlocks } from '@wordpress/block-library';

/**
 * Internal dependencies
 */
import { editorLoaded } from '../../utils/bridge';
import { postTypeEntities } from '../../utils/post-type-entities';

export function useEditorSetup(post) {
	const { addEntities, receiveEntityRecords } = useDispatch(coreStore);
	const { setEditedPost, setupEditor } = useDispatch(editorStore);

	useEffect(() => {
		addEntities(postTypeEntities);
		receiveEntityRecords('postType', post.type, post);

		setupEditor(post, {});
		registerCoreBlocks();

		editorLoaded();
		// Temp, check why this isn't being called in the provider.
		setEditedPost(post.type, post.id);

		return () => {
			getBlockTypes().forEach((block) => {
				unregisterBlockType(block.name);
			});
		};
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, []);
}
