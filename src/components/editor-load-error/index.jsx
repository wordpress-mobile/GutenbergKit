/**
 * WordPress dependencies
 */
import { Notice } from '@wordpress/components';
import { __ } from '@wordpress/i18n';

/**
 * Internal dependencies
 */
import './style.scss';

const EditorLoadError = ( { error } ) => {
	return (
		<div className="gutenberg-kit-editor-load-error">
			<Notice
				status="error"
				isDismissible={ false }
				className="gutenberg-kit-editor-load-error__notice"
			>
				<h1>{ __( 'Editor Load Error', 'gutenberg-kit' ) }</h1>
				<p className="gutenberg-kit-editor-load-error__message">
					{ __(
						'Sorry, loading the experimental editor failed. Please try reopening the editor.',
						'gutenberg-kit'
					) }
				</p>
				<p className="gutenberg-kit-editor-load-error__message">
					{ __(
						'If the problem persists, please contact support or disable the experimental editor within the app settings.',
						'gutenberg-kit'
					) }
				</p>
				{ error && (
					<details className="gutenberg-kit-editor-load-error__details">
						<summary className="gutenberg-kit-editor-load-error__message">
							<i>
								{ __(
									'Tap to view error details',
									'gutenberg-kit'
								) }
							</i>
						</summary>

						<pre className="gutenberg-kit-editor-load-error__details">
							{ error.message || error }
						</pre>
					</details>
				) }
			</Notice>
		</div>
	);
};

export default EditorLoadError;
