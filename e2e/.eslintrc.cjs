module.exports = {
	extends: [ 'plugin:@wordpress/eslint-plugin/test-playwright' ],
	rules: {
		// Allow non-literal titles for test.describe/test parameterized tests.
		'playwright/valid-title': 'off',
		// The WordPress ESLint config enforces jsdoc on all functions, but
		// test files don't benefit from it.
		'jsdoc/require-jsdoc': 'off',
	},
};
