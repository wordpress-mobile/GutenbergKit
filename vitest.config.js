/**
 * External dependencies
 */
import { defineConfig } from 'vite';
import { defaultExclude } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig( {
	plugins: [ react() ],
	test: {
		exclude: [ ...defaultExclude, 'build/**', 'e2e/**/*.spec.js' ],
		setupFiles: [ './vitest.setup.js' ],
		css: false,
		environment: 'jsdom',
	},
} );
