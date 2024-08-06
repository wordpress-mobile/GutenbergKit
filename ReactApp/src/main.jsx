/**
 * External dependencies
 */
import React from 'react';
import ReactDOM from 'react-dom/client';

/**
 * Internal dependencies
 */
import './misc/api-fetch-setup';
import App from './App.jsx';
import './index.css';

ReactDOM.createRoot(document.getElementById('root')).render(
	<React.StrictMode>
		<App />
	</React.StrictMode>
);
