import fs from 'fs';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { defaultRequestToExternal } from '@wordpress/dependency-extraction-webpack-plugin/lib/util.js';

const externalMap = new Map();

function externalize(id) {
	const result = defaultRequestToExternal(id);
	const isExternal = !!result;
	if (isExternal) externalMap.set(id, result);
	return isExternal;
}

function globalize(id) {
	let globalName = externalMap.get(id);
	if (Array.isArray(globalName)) return globalName.join('.');
	return globalName;
}

const tagsData = JSON.parse(fs.readFileSync('./assets.json', 'utf-8'));

// https://vitejs.dev/config/
export default defineConfig({
	base: '',
	build: {
		rollupOptions: {
			external: externalize,
			output: {
				format: 'iife',
				globals: globalize,
				entryFileNames: `assets/[name].js`,
				chunkFileNames: `assets/[name].js`,
				assetFileNames: `assets/[name].[ext]`,
			},
		},
	},
	plugins: [
		react({ jsxRuntime: 'classic' }),
		wordpressExternalsPlugin(),
		injectTagsPlugin(tagsData.scripts, tagsData.styles),
	],
});

function wordpressExternalsPlugin() {
	return {
		name: 'wordpress-externals-plugin',
		transform(code, id) {
			if (id.includes('node_modules')) {
				return;
			}

			// Transform @wordpress imports, including renames
			code = code.replace(
				/import\s*{([^}]+)}\s*from\s*['"]@wordpress\/([^'"]+)['"]/g,
				(match, imports, module) => {
					const importList = imports.split(',').map((i) => {
						const parts = i.trim().split(/\s+as\s+/);
						if (parts.length === 2) {
							// Handle rename
							return `${parts[0]}: ${parts[1]}`;
						}
						return i.trim();
					});

					// Convert module name to camelCase for wp.moduleName format
					const wpModule = module.replace(/-([a-z])/g, (g) =>
						g[1].toUpperCase()
					);

					return `const { ${importList.join(', ')} } = window.wp.${wpModule}`;
				}
			);

			return {
				code,
				map: null, // we're not generating sourcemaps for this transformation
			};
		},
	};
}

function injectTagsPlugin(scripts, stylesheets) {
	return {
		name: 'inject-tags-plugin',
		transformIndexHtml(html) {
			return {
				html,
				tags: [
					{
						tag: 'script',
						attrs: {
							id: 'gbkit-setup',
							src: './src/setup/dist/setup/assets/index.js',
						},
						injectTo: 'head',
					},
					...scripts
						.split(/\n(?=<script)/g)
						.map(createHtmlTagDescriptor),
					...stylesheets
						.split(/\n(?=<link|<style)/)
						.map(createHtmlTagDescriptor),
				],
			};
		},
	};
}

function createHtmlTagDescriptor(tagString) {
	const tag = tagString.match(/<(\w+)/)[1];

	const attrs = {};
	let attrMatches;
	if (tag === 'script') {
		attrMatches = tagString.match(/(\w+)="([^"]+)"/g);
	} else {
		attrMatches = tagString.match(/(\w+)='([^']+)'/g);
	}
	if (attrMatches) {
		attrMatches.forEach((attrMatch) => {
			const [attr, value] = attrMatch.split('=');
			attrs[attr] = value.slice(1, -1);
		});
	}

	// Discard remote api-fetch scripts as we must use the locally configured
	// copy.
	if (/\/api-fetch\//.test(attrs.src)) {
		return {};
	}

	const children = tagString.match(/>([\s\S]+)</);

	const injectTo = tag === 'script' ? 'body-prepend' : 'head';

	return {
		tag,
		attrs,
		children: children ? children[1] : '',
		injectTo,
	};
}
