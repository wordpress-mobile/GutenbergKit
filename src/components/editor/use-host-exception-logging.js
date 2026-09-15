/**
 * WordPress dependencies
 */
import { useEffect } from '@wordpress/element';
import { addAction, removeAction } from '@wordpress/hooks';

/**
 * Internal dependencies
 */
import { logException } from '../../utils/bridge';

/**
 * Logs errors caught by `@wordpress/editor` error boundaries nested inside the
 * editor, such as one a plugin renders. Those leave the editor usable, so they
 * are only logged; `EditorErrorBoundary` reports crashes of the editor itself.
 */
export function useHostExceptionLogging() {
	useEffect( () => {
		addAction(
			'editor.ErrorBoundary.errorLogged',
			'GutenbergKit',
			( error ) => {
				logException( error, {
					isHandled: true,
					handledBy: 'editor.ErrorBoundary.errorLogged',
				} );
			}
		);

		return () => {
			removeAction( 'editor.ErrorBoundary.errorLogged', 'GutenbergKit' );
		};
	}, [] );
}
