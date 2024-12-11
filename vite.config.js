/**
 * External dependencies
 */
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
	base: '',
	build: {
		outDir: '../dist',
		target: 'esnext',
		// Removes hashes from the filenames
		rollupOptions: {
			output: {
				entryFileNames: `assets/[name].js`,
				chunkFileNames: `assets/[name].js`,
				assetFileNames: `assets/[name].[ext]`,
			},
		},
	},
	plugins: [react()],
	root: 'src',
});
