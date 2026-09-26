/**
 * External dependencies
 */
import { defineConfig, globalIgnores } from 'eslint/config';
import wordpress from '@wordpress/eslint-plugin';
import reactRefresh from 'eslint-plugin-react-refresh';
import globals from 'globals';

export default defineConfig( [
	globalIgnores( [
		// Flat config, unlike eslintrc, does not ignore dot directories, so the
		// SwiftPM build directory has to be named explicitly.
		'.build/',
		'android/',
		'build/',
		'dist/',
		'e2e/test-results/',
		'ios/',
		'playwright-report/',
		'vendor/',
	] ),
	{
		files: [ '**/*.{js,jsx,cjs,mjs}' ],
		extends: [ wordpress.configs.recommended ],
		languageOptions: {
			globals: globals.browser,
		},
		settings: {
			'import/resolver': {
				// The WordPress config registers only the TypeScript resolver,
				// which honors `exports` and so resolves neither the
				// `@wordpress/block-editor` subpaths added in `patches/`, whose
				// targets omit the `.mjs` extension, nor
				// `@wordpress/preferences-persistence`, whose `types` condition
				// names build output it does not publish. The node resolver
				// ignores `exports` and resolves both.
				node: {
					extensions: [ '.js', '.jsx', '.mjs', '.cjs' ],
				},
			},
		},
		plugins: {
			'react-refresh': reactRefresh,
		},
		rules: {
			'react-refresh/only-export-components': [
				'warn',
				{ allowConstantExport: true },
			],
		},
	},
	{
		files: [ 'e2e/**/*.js' ],
		// Unit tests sit alongside the specs but run under vitest, whose `it()`
		// blocks the Playwright rules do not recognize as tests.
		ignores: [ 'e2e/**/*.test.js' ],
		extends: [ wordpress.configs[ 'test-playwright' ] ],
		rules: {
			// Discourage deprecated Playwright APIs in favor of locators, aligned
			// with the upstream Gutenberg ESLint configuration.
			'no-restricted-syntax': [
				'error',
				{
					selector: 'CallExpression[callee.property.name="$"]',
					message:
						'`$` is discouraged, please use `locator` instead.',
				},
				{
					selector: 'CallExpression[callee.property.name="$$"]',
					message:
						'`$$` is discouraged, please use `locator` instead.',
				},
				{
					selector:
						'CallExpression[callee.object.name="page"][callee.property.name="waitForTimeout"]',
					message: 'Prefer page.locator instead.',
				},
			],
		},
	},
] );
