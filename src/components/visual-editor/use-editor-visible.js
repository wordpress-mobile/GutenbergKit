/**
 * WordPress dependencies
 */
import { useEffect, useRef } from '@wordpress/element';

/**
 * Internal dependencies
 */
import { editorLoaded } from '../../utils/bridge';

/**
 * Returns a ref for observing an element and triggering the editorLoaded event when it becomes visible.
 *
 * @return {Object} The ref.
 */
export const useEditorVisible = () => {
	const ref = useRef( null );

	useEffect( () => {
		const observer = new IntersectionObserver( ( entries ) => {
			entries.forEach( ( entry ) => {
				if ( entry.isIntersecting ) {
					editorLoaded();
				}
			} );
		} );

		observer.observe( ref.current );

		return () => observer.disconnect();
	}, [ ref ] );

	return ref;
};
