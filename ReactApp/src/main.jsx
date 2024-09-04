/**
 * WordPress dependencies
 */
import apiFetch from '@wordpress/api-fetch';
import { createRoot, StrictMode } from '@wordpress/element';

/**
 * Internal dependencies
 */
import { getGBKit } from './misc/store.js';
import { initializeApiFetch } from './misc/api-fetch-setup';
import App from './App.jsx';
import './index.css';

window.GBKit = getGBKit();
window.wp = window.wp || {};
window.wp.apiFetch = initializeApiFetch(apiFetch);

createRoot(document.getElementById('root')).render(
	<StrictMode>
		<App />
	</StrictMode>
);
