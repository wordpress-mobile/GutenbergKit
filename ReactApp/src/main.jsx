/**
 * WordPress dependencies
 */
import { createRoot, StrictMode } from '@wordpress/element';

/**
 * Internal dependencies
 */
import { initializeApiFetch } from './misc/api-fetch-setup';
import { getGBKit } from './misc/store.js';
import App from './App.jsx';
import './index.css';

window.GBKit = getGBKit();
initializeApiFetch();

createRoot(document.getElementById('root')).render(
	<StrictMode>
		<App />
	</StrictMode>
);
