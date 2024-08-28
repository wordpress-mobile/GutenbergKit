/**
 * External dependencies
 */
import { defineConfig } from 'vite';

export default defineConfig({
	base: '',
	build: {
		lib: {
			entry: './index.js',
			name: 'setup',
			fileName: (format) => `setup.${format}.js`,
		},
		rollupOptions: {
			output: {
				format: 'iife',
				entryFileNames: `assets/[name].js`,
				chunkFileNames: `assets/[name].js`,
				assetFileNames: `assets/[name].[ext]`,
			},
		},
	},
});
