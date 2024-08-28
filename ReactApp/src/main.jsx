/**
 * WordPress dependencies
 */
import { createRoot, StrictMode } from '@wordpress/element';
import apiFetch from '@wordpress/api-fetch';
import { dispatch } from '@wordpress/data';
import { store as blockEditorStore } from '@wordpress/block-editor';

/**
 * Internal dependencies
 */
import { initializeApiFetch } from './misc/api-fetch-setup';
import { getGBKit } from './misc/store.js';
import App from './App.jsx';
import './index.css';

window.GBKit = getGBKit();
initializeApiFetch();

// TEMP: This should be fetched from the host apps.
apiFetch({ path: `/wp-block-editor/v1/settings` })
	.then((editorSettings) => {
		dispatch(blockEditorStore).updateSettings(editorSettings);
	})
	.catch((error) => {
		console.error('Error fetching editor settings:', error);
	});

createRoot(document.getElementById('root')).render(
	<StrictMode>
		<App />
	</StrictMode>
);
