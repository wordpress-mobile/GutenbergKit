/**
 * External dependencies
 */
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { nodePolyfills } from 'vite-plugin-node-polyfills';

export default defineConfig( {
	base: '',
	build: {
		outDir: '../dist',
		target: 'esnext',
		rollupOptions: {
			output: {
				manualChunks: {
					// Chunk to avoid circular dependency
					bridge: [ 'src/utils/bridge.js' ],
					// The dynamic import of this module fails without this
					editor: [ 'src/utils/editor.jsx' ],
				},
			},
		},
	},
	plugins: [ nodePolyfills(), react() ],
	root: 'src',
	css: {
		preprocessorOptions: {
			scss: {
				quietDeps: true,
			},
		},
	},
} );
