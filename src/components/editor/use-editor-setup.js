import { useEffect } from '@wordpress/element';
import { useDispatch, useSelect } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';
import { store as editorStore } from '@wordpress/editor';

export function useEditorSetup( post ) {
	const { setupEditor } = useDispatch( editorStore );
	const template = useSelect(
		( select ) => select( coreStore ).getPostType( post.type )?.template,
		[ post.type ]
	);

	useEffect( () => {
		setupEditor( post, {}, getNewPostTemplate( post, template ) );

		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, [] );
}

/**
 * Returns the post type's template to apply to the post, if any.
 *
 * Core applies the template to every new post, replacing blocks that don't
 * match it. Unlike WP Admin's auto-drafts, a new post can hold content from the
 * host, such as a local draft, so the template applies only when it's empty.
 *
 * @param {Object} post       The post.
 * @param {Array}  [template] The post type's block template.
 * @return {Array|undefined} The template, or undefined to leave the post as is.
 */
function getNewPostTemplate( post, template ) {
	if ( ! template?.length || post.content?.raw?.trim() ) {
		return undefined;
	}

	return template;
}
