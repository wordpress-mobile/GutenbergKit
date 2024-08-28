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
	plugins: [react({ jsxRuntime: 'classic' })],
});
