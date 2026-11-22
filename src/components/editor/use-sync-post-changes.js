import { useEffect, useRef } from '@wordpress/element';
import { useSelect } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';
import { onPostChanged } from '../../utils/bridge';

/**
 * How long the edits have to stay unchanged before the host hears of them, so
 * that typing sends one report rather than one per keystroke.
 */
const REPORT_DELAY_MS = 300;

/**
 * Tells the host whenever the edits change, whatever they are: the content, a
 * setting such as the categories, or a field a plugin adds. Saving changes them
 * too, as it clears them.
 *
 * Edits made while the editor sets up, such as a new post's template, aren't
 * reported.
 */
export function useSyncPostChanges() {
	const editsReference = useSelect(
		( select ) => select( coreStore ).getReferenceByDistinctEdits(),
		[]
	);
	const initialReference = useRef( editsReference );

	useEffect( () => {
		if ( editsReference === initialReference.current ) {
			return;
		}

		const timer = setTimeout( onPostChanged, REPORT_DELAY_MS );
		return () => clearTimeout( timer );
	}, [ editsReference ] );
}
