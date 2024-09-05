/**
 * WordPress dependencies
 */
import { store as editorStore } from '@wordpress/editor';
import { useSelect } from '@wordpress/data';
import { privateApis as blockEditorPrivateApis } from '@wordpress/block-editor';
import { store as editPostStore } from '@wordpress/edit-post';
import { useMemo } from '@wordpress/element';

// Internal imports
import { unlock } from '../lock-unlock';

const { getLayoutStyles } = unlock(blockEditorPrivateApis);

// This should be exported from Core so no reimplementation is needed.
export function useEditorStyles() {
	const { hasThemeStyleSupport, editorSettings } = useSelect((select) => {
		return {
			hasThemeStyleSupport:
				select(editPostStore).isFeatureActive('themeStyles'),
			editorSettings: select(editorStore).getEditorSettings(),
		};
	}, []);

	return useMemo(() => {
		const defaultEditorStyles = [
			...(editorSettings?.defaultEditorStyles ?? []),
		];

		if (!editorSettings.disableLayoutStyles && !hasThemeStyleSupport) {
			defaultEditorStyles.push({
				css: getLayoutStyles({
					style: {},
					selector: 'body',
					hasBlockGapSupport: false,
					hasFallbackGapSupport: true,
					fallbackGapValue: '0.5em',
				}),
			});
		}

		const baseStyles = hasThemeStyleSupport
			? editorSettings.styles ?? []
			: defaultEditorStyles;

		return baseStyles;
	}, [
		editorSettings.defaultEditorStyles,
		editorSettings.disableLayoutStyles,
		editorSettings.styles,
		hasThemeStyleSupport,
	]);
}
