/**
 * WordPress dependencies
 */
import { __ } from '@wordpress/i18n';

/**
 * Internal dependencies
 */
import './style.scss';

/**
 * Displays an error notice when the editor fails to load.
 *
 * Simple error message avoids `@wordpress` components to avoid
 * complex dependency management during editor initialization.
 *
 * @param {Object} props       Component props
 * @param {string} props.error Error message displayed in the notice
 *
 * @return {Element} Editor load error component
 */
const EditorLoadError = ( { error } ) => {
	const errorMessage = error.message || error;
	let errorDetails = '';
	if ( errorMessage ) {
		errorDetails = `
			<details>
				<summary class="gutenberg-kit-editor-load-error__message">
					<i>
						${ __( 'Tap to view error details', 'gutenberg-kit' ) }
					</i>
				</summary>
				<pre class="gutenberg-kit-editor-load-error__code">${ errorMessage }</pre>
			</details>`;
	}

	return `
		<div class="gutenberg-kit-editor-load-error">
			<div class="gutenberg-kit-editor-load-error__notice">
				<h1 class="gutenberg-kit-editor-load-error__heading">${ __(
					'Editor load error',
					'gutenberg-kit'
				) }</h1>
				<p class="gutenberg-kit-editor-load-error__message">
					${ __(
						'Sorry, loading the editor failed. Please try again.',
						'gutenberg-kit'
					) }
				</p>
				${ errorDetails }
			</div>
		</div>
	`;
};

export default EditorLoadError;
