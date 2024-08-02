import { getGBKit } from './Helpers.js';
import apiFetch from '@wordpress/api-fetch';

export async function loadRemoteEditor(global) {
	const { siteUrl } = getGBKit();
	if (!siteUrl) {
		console.error('No site URL found in GBKit');
		return;
	}

	// Define necessary `wp` globals prior to loading remote editor scripts
	global.wp = global.wp || {};
	global.wp.apiFetch = apiFetch;

	apiFetch.use(apiFetch.createRootURLMiddleware(`${siteUrl}/wp-json/`));
	apiFetch.setFetchHandler(fetchHandler);

	try {
		const { styles, scripts } = await apiFetch({
			path: '/beae/v1/editor-assets',
		});
		injectStyles(styles);
		await injectScripts(scripts);
	} catch (error) {
		console.error('Remote editor loading failed:', error);
	}
}

// TODO: Increase fetch handler robustness and error handling
function fetchHandler(options) {
	const { apiToken } = window.GBKit;
	const { path, url, ...rest } = options;

	if (!apiToken) {
		console.warn('No API token found in GBKit');
	}

	return fetch(url || path, {
		...rest,
		mode: 'cors',
		headers: {
			Authorization: `Bearer ${apiToken}`,
		},
	})
		.then((response) => {
			if (!response.ok) {
				throw new Error(`API request failed: ${response.status}`);
			}

			return response;
		})
		.then((response) => response.json());
}

function injectStyles(styles) {
	const styleContainer = document.createElement('div');
	styleContainer.innerHTML = styles.replace(/(href=['"])\/\//g, '$1https://');
	document.head.appendChild(styleContainer);
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

function injectScripts(scripts) {
	const scriptContainer = document.createElement('div');
	const sanitizedScripts = scripts
		.replace(/\\"/g, "'")
		.replace(/src="\/\//g, 'src="https://');
	scriptContainer.innerHTML = sanitizedScripts;
	const scriptTags = Array.from(scriptContainer.querySelectorAll('script'));

	function loadScript(index) {
		if (index >= scriptTags.length) return Promise.resolve();

		return new Promise((resolve) => {
			const scriptTag = scriptTags[index];

			if (scriptTag.src && excludedScripts.test(scriptTag.src)) {
				return resolve();
			}

			const newScript = document.createElement('script');

			if (scriptTag.src) {
				newScript.src = scriptTag.src;
				newScript.onload = () => resolve();
				newScript.onerror = () => resolve(); // Continue even if a script fails to load
			} else {
				const blob = new Blob([scriptTag.textContent], {
					type: 'application/javascript',
				});
				const url = URL.createObjectURL(blob);
				newScript.src = url;
				newScript.onload = () => {
					URL.revokeObjectURL(url);
					resolve();
				};
				newScript.onerror = () => {
					URL.revokeObjectURL(url);
					resolve(); // Continue even if a script fails to load
				};
			}

			if (scriptTag.id) {
				newScript.id = scriptTag.id;
			}

			document.body.appendChild(newScript);
		}).then(() => loadScript(index + 1));
	}

	return loadScript(0);
}
