/**
 * WordPress dependencies
 */
import { useEffect } from '@wordpress/element';
import { addAction, removeAction } from '@wordpress/hooks';

/**
 * Internal dependencies
 */
import { editorUnavailable, logException } from '../../utils/bridge';

/**
 * Reports editor crashes to the native host.
 *
 * The `editor.ErrorBoundary.errorLogged` action is emitted only by the
 * editor-level `ErrorBoundary`, so it doubles as the signal that the editor
 * is gone: React unmounts the subtree, which deletes every `window.editor.*`
 * bridge method. The host is told so it can stop calling them, rather than
 * raising a `TypeError` on every subsequent call.
 *
 * Must be used outside the `ErrorBoundary` it reports on, so the listener
 * survives the crash.
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
				editorUnavailable();
			}
		);

		return () => {
			removeAction( 'editor.ErrorBoundary.errorLogged', 'GutenbergKit' );
		};
	}, [] );
}
