/**
 * WordPress dependencies
 */
import defaultEditorStyles from '@wordpress/block-editor/build-style/default-editor-styles.css?inline';
import { store as editorStore } from '@wordpress/editor';
import { select } from '@wordpress/data';

/**
 * Returns a default editor settings object to use when a site cannot provide
 * its own editor settings due to lacking the necessary experimental REST API
 * endpoint provided by the Gutenberg plugin
 *
 * @see https://github.com/WordPress/gutenberg/blob/d97807b50f756126798a04a5ae94745aee19356d/lib/experimental/class-wp-rest-block-editor-settings-controller.php
 * @see https://github.com/WordPress/gutenberg/pull/64448
 *
 * @return {Object} The default editor settings object
 */
export function getDefaultEditorSettings() {
	const settings = select( editorStore ).getEditorSettings();
	const defaultEditorColors = settings?.colors;
	const defaultEditorGradients = settings?.gradients;

	return {
		defaultEditorStyles: [ { css: defaultEditorStyles } ],
		__experimentalFeatures: {
			blocks: {}, // Avoid errors from blocks relying upon block settings
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
