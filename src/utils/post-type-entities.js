import { parse } from '@wordpress/blocks';

/**
 * Builds an entity configuration for a post type core-data did not load.
 *
 * Core loads post type entities from the `/wp/v2/types` response, so this is
 * only a fallback for a type missing from it. It mirrors the configuration
 * core builds in `loadPostTypeEntities`, so saves behave the same either way.
 *
 * @param {Object} post               The post being edited.
 * @param {string} post.type          The post type.
 * @param {string} post.restBase      The REST API base path for the post type.
 * @param {string} post.restNamespace The REST API namespace for the post type.
 * @return {Object} The entity configuration.
 */
export function buildPostTypeEntity( { type, restBase, restNamespace } ) {
	const baseURL = `/${ restNamespace }/${ restBase }`;

	return {
		kind: 'postType',
		name: type,
		baseURL,
		baseURLParams: { context: 'edit' },
		transientEdits: {
			// Core also defines a `write`, which nothing calls.
			blocks: {
				read: ( record ) => parse( record.content?.raw ?? '' ),
			},
			selection: true,
		},
		mergedEdits: { meta: true },
		rawAttributes: [ 'title', 'excerpt', 'content' ],
		__unstablePrePersist: prePersistPostType,
		__unstable_rest_base: restBase,
		supportsPagination: true,
		getRevisionsUrl: ( parentId, revisionId ) =>
			`${ baseURL }/${ parentId }/revisions${
				revisionId ? '/' + revisionId : ''
			}`,
		revisionKey: 'id',
	};
}

/**
 * Applies the edits core makes before saving a post.
 *
 * Mirrors core-data's `prePersistPostType`, which is not exported, for
 * non-template post types.
 *
 * Exported for testing only.
 *
 * @param {Object} persistedRecord The persisted post.
 * @param {Object} edits           The edits being saved.
 * @return {Object} The additional edits.
 */
export function prePersistPostType( persistedRecord, edits ) {
	const newEdits = {};

	if ( persistedRecord?.status === 'auto-draft' ) {
		// Saving an auto-draft should create a draft by default.
		if ( ! edits.status ) {
			newEdits.status = 'draft';
		}

		// Fix the auto-draft default title.
		if (
			( ! edits.title || edits.title === 'Auto Draft' ) &&
			( ! persistedRecord?.title ||
				persistedRecord?.title === 'Auto Draft' )
		) {
			newEdits.title = '';
		}
	}

	return newEdits;
}
