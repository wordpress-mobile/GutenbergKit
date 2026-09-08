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
 * Reports editor crashes to the native host.
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
			}
		);

		return () => {
			removeAction( 'editor.ErrorBoundary.errorLogged', 'GutenbergKit' );
		};
	}, [] );
}
