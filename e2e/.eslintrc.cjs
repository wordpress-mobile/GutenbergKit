module.exports = {
	extends: [ 'plugin:@wordpress/eslint-plugin/test-playwright' ],
	rules: {
		// Allow non-literal titles for test.describe/test parameterized tests.
		'playwright/valid-title': 'off',
		// The WordPress ESLint config enforces jsdoc on all functions, but
		// test files don't benefit from it.
		'jsdoc/require-jsdoc': 'off',
		// Discourage deprecated Playwright APIs in favor of locators, aligned
		// with the upstream Gutenberg ESLint configuration.
		'no-restricted-syntax': [
			'error',
			{
				selector: 'CallExpression[callee.property.name="$"]',
				message: '`$` is discouraged, please use `locator` instead.',
			},
			{
				selector: 'CallExpression[callee.property.name="$$"]',
				message: '`$$` is discouraged, please use `locator` instead.',
			},
			{
				selector:
					'CallExpression[callee.object.name="page"][callee.property.name="waitForTimeout"]',
				message: 'Prefer page.locator instead.',
			},
		],
	},
};
