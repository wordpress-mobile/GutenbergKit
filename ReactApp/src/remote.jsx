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
		const scripts = await apiFetch({
			url: `${siteURL}/wp-json/__experimental/scripts?context=edit`,
		});
		const styles = await apiFetch({
			url: `${siteURL}/wp-json/__experimental/styles?context=edit`,
		});
		return;
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
		console.error('Error initializing the remote editor', error);
	}
}

/**
 * Load the asset files for a block
 */
async function loadAssets(assets) {
	/*
	 * Load each asset in order, as they may depend upon an earlier loaded script.
	 * Stylesheets and Inline Scripts will resolve immediately upon insertion.
	 */
	for (const asset of assets) {
		await loadAsset(asset);
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
 * @param {Object} asset An asset objcet to inject.
 *
 * @return {Promise} Promise which will resolve when the asset is loaded.
 */
function loadAsset(asset, type = 'script') {
	return new Promise((resolve) => {
		/*
		 * Reconstruct the passed element, this is required as inserting the Node directly
		 * won't always fire the required onload events, even if the asset wasn't already loaded.
		 */
		const newNode = document.createElement(type);
		newNode.id = asset.handle;
		newNode.src = asset.url;

		// Append inline <script> contents.
		if (asset.extra) {
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
