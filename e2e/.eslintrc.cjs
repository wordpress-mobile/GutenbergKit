module.exports = {
	extends: [ 'plugin:@wordpress/eslint-plugin/test-playwright' ],
	rules: {
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
