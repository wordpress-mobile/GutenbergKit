import { dispatch, resolveSelect, select } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';
import { getGBKit } from './bridge';
import { warn } from './logger';
import { buildPostTypeEntity } from './post-type-entities';

/**
 * @typedef {import('./bridge').Post} Post
 */

/**
 * Seeds core-data with the post being edited before the editor renders.
 *
 * The post is received as the persisted record and its `getEntityRecord`
 * resolution is marked finished, so core-data never fetches the post and
 * replaces the host's content, which may hold edits not yet uploaded.
 *
 * Adapted from `primePostEntity` in
 * https://github.com/wordpress-mobile/GutenbergKit/pull/445.
 *
 * @param {Post} post The post from the host.
 * @return {Promise<void>} Resolves once the post is seeded.
 */
export async function primePostEntity( post ) {
	await registerPostTypeEntity( post );

	const { receiveEntityRecords, finishResolution } = dispatch( coreStore );
	receiveEntityRecords( 'postType', post.type, buildPostRecord( post ) );
	finishResolution( 'getEntityRecord', [ 'postType', post.type, post.id ] );
}

/**
 * Ensures core-data has an entity configuration for the post's type.
 *
 * Core builds the configurations from the `/wp/v2/types` response, which hosts
 * preload. A fallback is registered only for a type missing from it.
 *
 * @param {Post} post The post from the host.
 * @return {Promise<void>} Resolves once the configuration is registered.
 */
async function registerPostTypeEntity( post ) {
	await resolveSelect( coreStore ).getEntitiesConfig( 'postType' );

	if ( select( coreStore ).getEntityConfig( 'postType', post.type ) ) {
		return;
	}

	warn( `Post type "${ post.type }" not loaded; using a fallback config` );
	dispatch( coreStore ).addEntities( [ buildPostTypeEntity( post ) ] );
}

/**
 * Builds the persisted record for the post.
 *
 * The host sends only a few fields, so the server record the host preloaded
 * supplies the rest (dates, author, terms, meta, etc.). The host's title and
 * content take precedence over the server's.
 *
 * @param {Post} post The post from the host.
 * @return {Object} The record.
 */
function buildPostRecord( post ) {
	const serverRecord = getPreloadedPost( post );

	if ( ! serverRecord ) {
		return post;
	}

	return {
		...serverRecord,
		title: { ...serverRecord.title, raw: post.title.raw },
		content: { ...serverRecord.content, raw: post.content.raw },
	};
}

/**
 * Returns the server record the host preloaded for the post, if any.
 *
 * @param {Post} post The post from the host.
 * @return {Object|null} The record, or null when not preloaded.
 */
function getPreloadedPost( post ) {
	const { preloadData } = getGBKit();
	const path = `/${ post.restNamespace }/${ post.restBase }/${ post.id }?context=edit`;

	return preloadData?.[ path ]?.body ?? null;
}
