import { createHash } from 'crypto';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import {
	defaultRequestToExternal,
	defaultRequestToHandle,
} from '@wordpress/dependency-extraction-webpack-plugin/lib/util.js';
import json2php from 'json2php';

import packageMeta from './package.json';

const kebabToCamel = (str) =>
	str.replace(/-(\w)/, (all, g1) => g1.toUpperCase());

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

function assetize() {
	return {
		name: 'assetize',

		generateBundle(options, bundle) {
			Object.entries(bundle).forEach(([fileName, fileInfo]) => {
				if (!fileInfo.isAsset) {
					const { imports, code } = fileInfo;
					const scriptMeta = {
						dependencies: imports
							.map(defaultRequestToHandle)
							.filter((o) => o != null),
						version: createHash('sha1')
							.update(code)
							.digest('hex')
							.slice(0, 20),
					};
					this.emitFile({
						type: 'asset',
						fileName: fileInfo.fileName.replace(
							/\.js$/,
							'.asset.php'
						),
						source: `<?php return ${json2php(scriptMeta)};\n`,
					});
				}
			});
		},
	};
}

// https://vitejs.dev/config/
export default defineConfig({
	base: '',
	build: {
		lib: {
			entry: './src/index.js',
			name: kebabToCamel(packageMeta.name),
			formats: ['iife'],
		},
		rollupOptions: {
			external: externalize,
			output: {
				globals: globalize,
				entryFileNames: `assets/${packageMeta.name}.js`,
				chunkFileNames: `assets/[name].js`,
				assetFileNames: `assets/[name].[ext]`,
			},
		},
	},
	plugins: [react({ jsxRuntime: 'classic' }), assetize()],
});
