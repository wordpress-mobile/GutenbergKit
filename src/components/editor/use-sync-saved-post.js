import { useEffect, useRef } from '@wordpress/element';
import { useSelect } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';
import { store as editorStore } from '@wordpress/editor';
import { onSavedPostChanged } from '../../utils/bridge';

/**
 * Tells the host whenever core-data's saved version of the post changes,
 * whatever changed it: a save, a read of the post, a list that includes it, or
 * a plugin storing a copy of it.
 *
 * The saved version is what the editor believes the server has. Each report
 * carries its `modified_gmt` and the fields that changed in it, so the host can
 * check it against what it knows the server has.
 *
 * Switching the editor to a new post ID starts over from that post's saved
 * version, without a report.
 *
 * @return {void}
 */
export function useSyncSavedPost() {
	const { postKey, savedPost } = useSelect( ( select ) => {
		const { getCurrentPostType, getCurrentPostId } = select( editorStore );
		const type = getCurrentPostType();
		const id = getCurrentPostId();
		return {
			postKey: `${ type }/${ id }`,
			savedPost: select( coreStore ).getEntityRecord(
				'postType',
				type,
				id
			),
		};
	}, [] );
	const lastSeen = useRef( { postKey, savedPost } );

	useEffect( () => {
		const last = lastSeen.current;
		lastSeen.current = { postKey, savedPost };

		if (
			last.postKey !== postKey ||
			last.savedPost === savedPost ||
			! last.savedPost ||
			! savedPost
		) {
			return;
		}

		onSavedPostChanged( {
			modified_gmt: savedPost.modified_gmt,
			fields: changedFields( last.savedPost, savedPost ),
		} );
	}, [ postKey, savedPost ] );
}

/**
 * The fields of `next` whose values differ from `previous`'s.
 *
 * @param {Object} previous The earlier version.
 * @param {Object} next     The later version.
 * @return {Object} The changed fields, with their values in `next`.
 */
function changedFields( previous, next ) {
	return Object.fromEntries(
		Object.entries( next ).filter(
			( [ key, value ] ) =>
				JSON.stringify( value ) !== JSON.stringify( previous[ key ] )
		)
	);
}
