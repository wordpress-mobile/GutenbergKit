module.exports = {
	root: true,
	extends: [ 'plugin:@wordpress/eslint-plugin/recommended' ],
	env: {
		browser: true,
		es2020: true,
	},
	parserOptions: {
		ecmaVersion: 'latest',
		sourceType: 'module',
	},
	plugins: [ 'react-refresh' ],
	rules: {
		'react-refresh/only-export-components': [
			'warn',
			{ allowConstantExport: true },
		],
	},
	settings: {
		'import/resolver': {
			node: {
				// Matches file extensions supported by WordPress build tools
				// See: https://github.com/WordPress/gutenberg/blob/760acec3522516c2212e0213ff10cd2a8c9e8df0/tools/eslint/import-resolver.js#L15
				extensions: [ '.js', '.jsx', '.mjs', '.cjs' ],
			},
		},
	},
};
