/** @type {import('stylelint').Config} */
export default {
	extends: '@wordpress/stylelint-config/scss',
	plugins: ['stylelint-plugin-logical-css'],
	rules: {
		'plugin/use-logical-properties-and-values': [
			true,
			{
				ignore: [
					// Doesn't affect RTL styles
					'border-bottom',
					'border-top',
					'width',
					'min-width',
					'max-width',
					'height',
					'min-height',
					'max-height',
					'margin-top',
					'margin-bottom',
					'overflow-x',
					'overflow-y',
					'padding-top',
					'padding-bottom',
					'scroll-margin-top',
					'scroll-margin-bottom',
					'top',
					'bottom',
				],
			},
		],

		// The rules below are relaxed the same way upstream Gutenberg relaxes them
		// (see WordPress/gutenberg's tools/stylelint/config.js) when applying this
		// shared config to a codebase that predates it. They flag pre-existing
		// formatting/selector-naming conventions unrelated to RTL/logical CSS, and
		// are out of scope for this initial adoption.
		'comment-empty-line-before': null,
		'no-descending-specificity': null,
		'rule-empty-line-before': null,
		'scss/comment-no-empty': null,
		'scss/selector-no-redundant-nesting-selector': null,
		'selector-class-pattern': [
			'^[a-z][a-z0-9]*(?:(?:__|--|-)[a-z0-9]+)*$',
			{
				message:
					'Selector should use lowercase class segments separated with hyphens, double hyphens, or double underscores (selector-class-pattern)',
			},
		],
	},
};
