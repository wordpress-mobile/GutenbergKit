/**
 * WordPress dependencies
 */
import { dispatch } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';

/**
 * Internal dependencies
 */
import { postTypeEntities } from './post-type-entities';

/**
 * Seeds the core-data store with the post's entity configuration and record
 * before the editor renders, so resolvers for `getEntityRecord` short-circuit
 * instead of firing a redundant network request.
 *
 * Must run before `<EditorProvider>` mounts.
 *
 * @param {Object} post The post object with type, id, restBase, and restNamespace.
 */
export function primePostEntity( post ) {
	const { addEntities, receiveEntityRecords, finishResolution } =
		dispatch( coreStore );

	addEntities( buildEntitiesForPostType( post ) );
	receiveEntityRecords( 'postType', post.type, post );
	finishResolution( 'getEntityRecord', [ 'postType', post.type, post.id ] );
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
