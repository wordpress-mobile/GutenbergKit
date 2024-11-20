/**
 * WordPress dependencies
 */
import { createRoot, StrictMode } from '@wordpress/element';
import apiFetch from '@wordpress/api-fetch';
import { dispatch } from '@wordpress/data';
import { store as editorStore } from '@wordpress/editor';
import { store as preferencesStore } from '@wordpress/preferences';

/**
 * Internal dependencies
 */
import { initializeApiFetch } from './utils/api-fetch-setup';
import { getGBKit, getPost } from './utils/bridge';
import App from './components/app';
import './index.css';

window.GBKit = getGBKit();
initializeApiFetch();
initializeEditor();

/**
 * Configure editor settings and styles, and render the editor.
 */
function initializeEditor() {
	const { themeStyles, siteApiRoot } = getGBKit();

	// TEMP: This should be fetched from the host apps.
	if (siteApiRoot?.length) {
		apiFetch({ path: `/wp-block-editor/v1/settings` })
			.then((editorSettings) => {
				dispatch(editorStore).updateEditorSettings(editorSettings);
			})
			.catch(() => {
				// TODO: Communicate helpful guidance to the user.
			});
	}

	dispatch(preferencesStore).setDefaults('core/edit-post', {
		themeStyles,
	});

	const post = getPost();
	const settings = {
		post,
	};

	createRoot(document.getElementById('root')).render(
		<StrictMode>
			<App {...settings} />
		</StrictMode>
	);
}
