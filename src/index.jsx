/**
 * WordPress dependencies
 */
import { createRoot, StrictMode } from '@wordpress/element';
import apiFetch from '@wordpress/api-fetch';
import { dispatch } from '@wordpress/data';
import { store as editorStore } from '@wordpress/editor';
import { store as preferencesStore } from '@wordpress/preferences';
import defaultEditorStyles from '@wordpress/block-editor/build-style/default-editor-styles.css?inline';

/**
 * Internal dependencies
 */
import { initializeApiFetch } from './utils/api-fetch-setup';
import { getGBKit, getPost } from './utils/bridge';
import EditorInterface from './components/editor-interface';
import './index.scss';
// The Vite query parameter breaks the linter's import resolution
// eslint-disable-next-line import/no-unresolved
import defaultThemeStyles from './default-theme-styles.scss?inline';

window.GBKit = getGBKit();
initializeApiFetch();
initializeEditor();

/**
 * Configure editor settings and styles, and render the editor.
 */
function initializeEditor() {
	const { themeStyles } = getGBKit();

	// TEMP: This should be fetched from the host apps.
	apiFetch({ path: `/wp-block-editor/v1/settings` })
		.then((editorSettings) => {
			dispatch(editorStore).updateEditorSettings(editorSettings);
		})
		.catch(() => {
			const editorSettings = {
				defaultEditorStyles: [
					{ css: defaultEditorStyles },
					{ css: defaultThemeStyles },
				],
			};
			dispatch(editorStore).updateEditorSettings(editorSettings);
		});

	dispatch(preferencesStore).setDefaults('core/edit-post', {
		themeStyles,
	});

	const post = getPost();
	const settings = {
		post,
	};

	createRoot(document.getElementById('root')).render(
		<StrictMode>
			<EditorInterface {...settings} />
		</StrictMode>
	);
}
