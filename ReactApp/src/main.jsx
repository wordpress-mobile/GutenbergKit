import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App.jsx';
import './index.css';

window.GBKit = getGBKit(window);

function getGBKit(global) {
	if (global.GBKit) {
		return global.GBKit;
	}

	const emptyObject = {};
	try {
		return JSON.parse(localStorage.getItem('GBKit')) || emptyObject;
	} catch (error) {
		console.error('Failed parsing GBKit from localStorage:', error);
		return emptyObject;
	}
}

ReactDOM.createRoot(document.getElementById('root')).render(
	<React.StrictMode>
		<App />
	</React.StrictMode>
);
