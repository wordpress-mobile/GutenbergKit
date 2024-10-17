/**
 * WordPress dependencies
 */
import apiFetch from '@wordpress/api-fetch';

/**
 * Internal dependencies
 */
import { getGBKit, getPost } from './misc/store.js';
import { initializeApiFetch } from './misc/api-fetch-setup.js';
import './index.css';

window.GBKit = getGBKit();
window.wp = window.wp || {};
window.wp.apiFetch = apiFetch;
initializeApiFetch();
initalizeRemoteEditor();

async function initalizeRemoteEditor() {
	try {
		const { themeStyles, siteURL, siteApiRoot } = getGBKit();
		const { styles, scripts } = await apiFetch({
			url: `${siteURL}/wp-json/__experimental/wp-block-editor/v1/editor-assets`,
		});
		await loadAssets([...styles, ...scripts].join(''));

		// Utilize remote-loaded globals rather than importing local modules
		const { dispatch } = window.wp.data;
		const { store: editorStore } = window.wp.editor;
		const { store: preferencesStore } = window.wp.preferences;

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
		const settings = { post };

		const { default: App } = await import('./App.jsx');
		const { createRoot, createElement, StrictMode } = window.wp.element;
		createRoot(document.getElementById('root')).render(
			createElement(StrictMode, null, createElement(App, settings))
		);
	} catch (error) {
		// Fallback to the local editor and display a notice. Because the remote
		// editor loading failed, it is more practical to rely upon the local
		// editor's scripts and styles for displaying the notice.
		window.location.href = 'index.html?error=remote_editor_load_error';
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
	return new Promise((resolve) => {
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
		newNode.onerror = (error) => {
			console.error('Error loading asset', error);
			resolve(false);
		};

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
