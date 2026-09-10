/**
 * WordPress dependencies
 */
import { addAction, hasAction } from '@wordpress/hooks';

/**
 * Internal dependencies
 */
import { editorUnavailable, logException } from './bridge';

const ERROR_LOGGED_ACTION = 'editor.ErrorBoundary.errorLogged';
const NAMESPACE = 'GutenbergKit';

/**
 * Reports editor crashes to the native host.
 *
 * The `editor.ErrorBoundary.errorLogged` action is emitted only by the
 * editor-level `ErrorBoundary`, so it doubles as the signal that the editor
 * is gone: React unmounts the subtree, which deletes every `window.editor.*`
 * bridge method. The host is told so it can stop calling them, rather than
 * raising a `TypeError` on every subsequent call.
 *
 * Must be called before the editor renders. The `ErrorBoundary` reports an
 * error thrown during its first render in the same commit that mounts it,
 * before any effect has run, so a listener registered from an effect misses
 * that crash.
 */
export function reportEditorCrashesToHost() {
	if ( hasAction( ERROR_LOGGED_ACTION, NAMESPACE ) ) {
		return;
	}

	addAction( ERROR_LOGGED_ACTION, NAMESPACE, ( error ) => {
		logException( error, {
			isHandled: true,
			handledBy: ERROR_LOGGED_ACTION,
		} );
		editorUnavailable();
	} );
}
