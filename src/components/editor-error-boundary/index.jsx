/**
 * WordPress dependencies
 */
import { Component } from '@wordpress/element';
import { __ } from '@wordpress/i18n';

/**
 * Internal dependencies
 */
import { editorUnavailable, logException } from '../../utils/bridge';
import { error } from '../../utils/logger';

/**
 * Replaces the editor with an error message when it crashes, and tells the
 * native host that the editor's bridge methods are gone.
 *
 * Used instead of `@wordpress/editor`'s `ErrorBoundary`, whose
 * `editor.ErrorBoundary.errorLogged` action is also emitted by boundaries
 * nested inside the editor. Those contain an error to one part of an editor
 * that still works, so they must not be reported as a crash.
 */
export default class EditorErrorBoundary extends Component {
	state = { hasError: false };

	static getDerivedStateFromError() {
		return { hasError: true };
	}

	componentDidCatch( exception, { componentStack } ) {
		try {
			logException( exception, {
				context: { componentStack },
				isHandled: true,
				handledBy: 'EditorErrorBoundary',
			} );
		} catch ( loggingError ) {
			error( 'Failed to log the editor crash', loggingError );
		} finally {
			// Failing to log the crash must not stop the host from learning that
			// the editor is gone.
			editorUnavailable();
		}
	}

	render() {
		if ( ! this.state.hasError ) {
			return this.props.children;
		}

		// Shows `@wordpress/editor`'s fallback message and styles. Its copy buttons
		// are omitted: the post content is cleared once the editor unmounts, and
		// the error is already logged to the host.
		return (
			<div className="editor-error-boundary">
				<p>
					{ __( 'The editor has encountered an unexpected error.' ) }
				</p>
			</div>
		);
	}
}
