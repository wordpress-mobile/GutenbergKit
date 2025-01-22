/**
 * WordPress dependencies
 */
import { useEffect } from '@wordpress/element';
import { addAction, removeAction } from '@wordpress/hooks';

/**
 * Internal dependencies
 */
import { logError } from '../../utils/bridge';

export function useHostErrorLogging() {
	useEffect(() => {
		addAction('editor.ErrorBoundary.errorLogged', 'GutenbergKit', logError);

		return () => {
			removeAction('editor.ErrorBoundary.errorLogged', 'GutenbergKit');
		};
	}, []);
}
