/**
 * External dependencies
 */
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react'; // eslint-disable-line import/no-unresolved

export default defineConfig( {
	plugins: [ react() ],
	test: {
		setupFiles: [ './vitest.setup.js' ],
		css: false,
		environment: 'jsdom',
	},
} );
