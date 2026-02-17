/**
 * WordPress dependencies
 */
import { useEffect } from '@wordpress/element';
import { useDispatch } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';
import { store as editorStore } from '@wordpress/editor';

/**
 * Internal dependencies
 */
import { postTypeEntities } from '../../utils/post-type-entities';

export function useEditorSetup( post ) {
	const { addEntities, receiveEntityRecords } = useDispatch( coreStore );
	const { setEditedPost, setupEditor } = useDispatch( editorStore );

	useEffect( () => {
		const entities = buildEntitiesForPostType( post );

		addEntities( entities );
		receiveEntityRecords( 'postType', post.type, post );

		setupEditor( post, {} );

		// Temp, check why this isn't being called in the provider.
		setEditedPost( post.type, post.id );

		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, [] );
}

/**
 * Builds the entity configuration list for the given post type.
 *
 * If the post type is already in the static list (post, page, etc.),
 * returns the static list as-is. Otherwise, dynamically creates an
 * entity configuration using the restBase and restNamespace from the post object.
 *
 * @param {Object} post - The post object with type, restBase, and restNamespace
 * @return {Array} Array of entity configurations
 */
function buildEntitiesForPostType( post ) {
	const isRegistered = postTypeEntities.some(
		( entity ) => entity.name === post.type
	);

	if ( isRegistered ) {
		return postTypeEntities;
	}

	const dynamicEntity = {
		kind: 'postType',
		name: post.type,
		baseURL: `/${ post.restNamespace }/${ post.restBase }`,
		transientEdits: {
			blocks: true,
			selection: true,
		},
		mergedEdits: {
			meta: true,
		},
		rawAttributes: [ 'title', 'excerpt', 'content' ],
	};

	return [ ...postTypeEntities, dynamicEntity ];
}
