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
	},
	plugins: [react()],
	root: 'src',
});
