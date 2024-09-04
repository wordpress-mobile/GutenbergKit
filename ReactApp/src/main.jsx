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
import { initializeApiFetch } from './misc/api-fetch-setup';
import { getGBKit } from './misc/store.js';
import { getPost } from './misc/Helpers';
import App from './App.jsx';
import './index.css';

window.GBKit = getGBKit();
initializeApiFetch();

function initializeEditor() {
	const { themeStyles, siteApiRoot } = window.GBKit;

	// TEMP: This should be fetched from the host apps.
	if (siteApiRoot?.length) {
		apiFetch({ path: `/wp-block-editor/v1/settings` })
			.then((editorSettings) => {
				dispatch(editorStore).updateEditorSettings(editorSettings);
			})
			.catch((error) => {
				console.error('Error fetching editor settings:', error);
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

initializeEditor();
