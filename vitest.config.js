/**
 * External dependencies
 */
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig( {
	plugins: [ react() ],
	test: {
		exclude: [ 'e2e/**/*.spec.js', 'node_modules/**' ],
		setupFiles: [ './vitest.setup.js' ],
		css: false,
		environment: 'jsdom',
	},
} );
