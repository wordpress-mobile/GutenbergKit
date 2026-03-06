/**
 * WordPress dependencies
 */
import defaultEditorStyles from '@wordpress/block-editor/build-style/default-editor-styles.css?inline';
import { store as editorStore } from '@wordpress/editor';
import { select } from '@wordpress/data';

/**
 * Returns a default editor settings object to use when a site cannot provide
 * its own editor settings due to lacking the necessary experimental REST API
 * endpoint provided by the Gutenberg plugin.
 *
 * @see https://github.com/WordPress/gutenberg/blob/d97807b50f756126798a04a5ae94745aee19356d/lib/experimental/class-wp-rest-block-editor-settings-controller.php
 *
 * @return {Object} The default editor settings object
 */
export function getDefaultEditorSettings() {
	const settings = select( editorStore ).getEditorSettings();
	const defaultEditorColors = settings?.colors;
	const defaultEditorGradients = settings?.gradients;

	return {
		/**
		 * These styles are used if the "no theme styles" options is triggered or on
		 * themes without their own editor styles.
		 *
		 * @see https://github.com/WordPress/wordpress-develop/blob/db9654e6d386c2c69401b9c77c6ce1ae7460a6e4/src/wp-includes/block-editor.php#L218C4-L218C23
		 */
		defaultEditorStyles: [ { css: defaultEditorStyles } ],
		__experimentalFeatures: {
			/**
			 * Avoid errors from blocks relying upon block settings.
			 *
			 * @see https://github.com/WordPress/gutenberg/pull/64448
			 */
			blocks: {},
			/**
			 * Enable the typography controls that WordPress core enables by
			 * default in its theme.json. This ensures blocks like Paragraph
			 * have text alignment in the toolbar and typography options in
			 * the block settings sidebar, even without editor settings from
			 * the site.
			 *
			 * @see https://github.com/WordPress/gutenberg/blob/d97807b50f756126798a04a5ae94745aee19356d/lib/theme.json
			 */
			typography: {
				customFontSize: true,
				defaultFontSizes: true,
				dropCap: true,
				fontSizes: {
					default: [
						{ name: 'Small', slug: 'small', size: '13px' },
						{ name: 'Medium', slug: 'medium', size: '20px' },
						{ name: 'Large', slug: 'large', size: '36px' },
						{
							name: 'Extra Large',
							slug: 'x-large',
							size: '42px',
						},
					],
				},
				fontStyle: true,
				fontWeight: true,
				letterSpacing: true,
				textAlign: true,
				textDecoration: true,
				textIndent: 'subsequent',
				textTransform: true,
			},
			/**
			 * Ensure themes lacking their own theme styles can customize blocks using
			 * the default editor colors and gradients. Mirrors the approach taken by
			 * the Gutenberg Mobile editor.
			 *
			 * @see https://github.com/WordPress/gutenberg/blob/d97807b50f756126798a04a5ae94745aee19356d/packages/block-editor/src/components/global-styles/use-global-styles-context.native.js#L410-L433
			 */
			color: {
				text: true,
				background: true,
				palette: {
					default: defaultEditorColors,
				},
				gradients: {
					default: defaultEditorGradients,
				},
				defaultPalette: defaultEditorColors?.length > 0,
				defaultGradients: defaultEditorGradients?.length > 0,
			},
		},
	};
}
