import { dispatch, resolveSelect, select } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';
import { getGBKit, getPostPath } from './bridge';
import { warn } from './logger';

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
	await Promise.all( [
		resolvePostTypeEntity( post ),
		post.status === 'auto-draft' && resolvePostType( post ),
	] );

	const { receiveEntityRecords, finishResolution } = dispatch( coreStore );
	receiveEntityRecords( 'postType', post.type, buildPostRecord( post ) );
	finishResolution( 'getEntityRecord', [ 'postType', post.type, post.id ] );
}

/**
 * Resolves core-data's entity configurations for post types.
 *
 * Core builds the configurations from the preloaded `/wp/v2/types` response,
 * which `withEditedPostType` ensures includes the post's type.
 *
 * @param {Post} post The post from the host.
 * @return {Promise<void>} Resolves once the configurations are resolved.
 */
async function resolvePostTypeEntity( post ) {
	await resolveSelect( coreStore ).getEntitiesConfig( 'postType' );

	if ( ! select( coreStore ).getEntityConfig( 'postType', post.type ) ) {
		warn( `No entity configuration for post type "${ post.type }"` );
	}
}

/**
 * Loads the post's type, whose template the editor setup applies to new posts.
 *
 * Only new posts wait for it, as hosts may not preload the type and other posts
 * don't need it to render. A failure is logged rather than thrown, as the
 * editor works without it.
 *
 * @param {Post} post The post from the host.
 * @return {Promise<void>} Resolves once the post type is loaded or failed.
 */
async function resolvePostType( post ) {
	try {
		await resolveSelect( coreStore ).getPostType( post.type );
	} catch ( err ) {
		warn( `Failed to load post type "${ post.type }"`, err );
	}
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
	const path = `${ getPostPath( post ) }?context=edit`;

	return preloadData?.[ path ]?.body ?? null;
}
