/**
 * WordPress dependencies
 */
import apiFetch from '@wordpress/api-fetch';

/**
 * Internal dependencies
 */
import { getGBKit } from './misc/store.js';
import { initializeApiFetch } from './misc/api-fetch-setup.js';
import { getRemoteEditor } from './misc/Helpers.js';
import './index.css';

window.GBKit = getGBKit();
window.wp = window.wp || {};
window.wp.apiFetch = initializeApiFetch(apiFetch);
initalizeRemoteEditor();

async function initalizeRemoteEditor() {
	try {
		const { styles, scripts } = await getRemoteEditor();
		await loadAssets([...styles, ...scripts].join(''));
		const { default: App } = await import('./App.jsx');
		const { createRoot, StrictMode } = window.wp.element;
		createRoot(document.getElementById('root')).render(
			<StrictMode>
				<App />
			</StrictMode>
		);
	} catch (error) {
		console.error('Error initializing the remote editor', error);
	}
}

/**
 * Load the asset files for a block
 */
async function loadAssets(html) {
	const doc = new window.DOMParser().parseFromString(html, 'text/html');

	const newAssets = Array.from(
		doc.querySelectorAll('link[rel="stylesheet"],script')
	).filter((asset) => asset.id && !excludedScripts.test(asset.src));

	/*
	 * Load each asset in order, as they may depend upon an earlier loaded script.
	 * Stylesheets and Inline Scripts will resolve immediately upon insertion.
	 */
	for (const newAsset of newAssets) {
		await loadAsset(newAsset);
	}
}

// Discard remote copies of localy-sourced Gutenberg packages to avoid conflicts
const localGutenbergPackages = ['api-fetch'];
const excludedScripts = new RegExp(
	localGutenbergPackages
		.flatMap((script) => [
			`wp-content/plugins/gutenberg/build/${script.replace(/\//g, '\\/')}\\b`,
			`wp-includes/js/dist/${script.replace(/\//g, '\\/')}\\b`,
		])
		.join('|')
);

/**
 * Load an asset for a block.
 *
 * This function returns a Promise that will resolve once the asset is loaded,
 * or in the case of Stylesheets and Inline JavaScript, will resolve immediately.
 *
 * @param {HTMLElement} el A HTML Element asset to inject.
 *
 * @return {Promise} Promise which will resolve when the asset is loaded.
 */
function loadAsset(el) {
	return new Promise((resolve, reject) => {
		/*
		 * Reconstruct the passed element, this is required as inserting the Node directly
		 * won't always fire the required onload events, even if the asset wasn't already loaded.
		 */
		const newNode = document.createElement(el.nodeName);

		['id', 'rel', 'src', 'href', 'type'].forEach((attr) => {
			if (el[attr]) {
				newNode[attr] = el[attr];
			}
		});

		// Append inline <script> contents.
		if (el.innerHTML) {
			newNode.appendChild(document.createTextNode(el.innerHTML));
		}

		newNode.onload = () => resolve(true);
		newNode.onerror = (error) =>
			reject(new Error(`Error loading asset: ${error}`));

		document.body.appendChild(newNode);

		// Resolve Stylesheets and Inline JavaScript immediately.
		if (
			'link' === newNode.nodeName.toLowerCase() ||
			('script' === newNode.nodeName.toLowerCase() && !newNode.src)
		) {
			resolve();
		}
	});
}
