/**
 * WordPress dependencies
 */
import { createRoot, StrictMode } from '@wordpress/element';
import apiFetch from '@wordpress/api-fetch';
import { dispatch } from '@wordpress/data';
import {
	EditorSnackbars,
	ErrorBoundary,
	store as editorStore,
} from '@wordpress/editor';
import { store as preferencesStore } from '@wordpress/preferences';
import defaultEditorStyles from '@wordpress/block-editor/build-style/default-editor-styles.css?inline';

/**
 * Internal dependencies
 */
import { initializeApiFetch } from './utils/api-fetch-setup';
import { getGBKit, getPost } from './utils/bridge';
import Editor from './components/editor';
import './index.scss';

window.GBKit = getGBKit();
initializeApiFetch();
initializeEditor();

/**
 * Configure editor settings and styles, and render the editor.
 */
function initializeEditor() {
	const { themeStyles, hideTitle } = getGBKit();

	// TEMP: This should be fetched from the host apps.
	apiFetch({ path: `/wp-block-editor/v1/settings` })
		.then((editorSettings) => {
			dispatch(editorStore).updateEditorSettings(editorSettings);
		})
		.catch(() => {
			const editorSettings = {
				defaultEditorStyles: [{ css: defaultEditorStyles }],
			};
			dispatch(editorStore).updateEditorSettings(editorSettings);
		});

	dispatch(preferencesStore).setDefaults('core/edit-post', {
		themeStyles,
	});

	const post = getPost();

	createRoot(document.getElementById('root')).render(
		<StrictMode>
			<ErrorBoundary>
				<Editor post={post} hideTitle={hideTitle}>
					<EditorSnackbars />
				</Editor>
			</ErrorBoundary>
		</StrictMode>
	);
}
