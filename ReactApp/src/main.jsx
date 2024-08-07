/**
 * External dependencies
 */
import React from 'react';
import ReactDOM from 'react-dom/client';

/**
 * Internal dependencies
 */
import { initializeApiFetch } from './misc/api-fetch-setup';
import App from './App.jsx';
import './index.css';

initializeApiFetch();

ReactDOM.createRoot(document.getElementById('root')).render(
	<React.StrictMode>
		<App />
	</React.StrictMode>
);
