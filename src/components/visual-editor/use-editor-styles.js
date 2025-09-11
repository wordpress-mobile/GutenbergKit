/**
 * WordPress dependencies
 */
import { store as editorStore } from '@wordpress/editor';
import { useSelect } from '@wordpress/data';
import { privateApis as blockEditorPrivateApis } from '@wordpress/block-editor';
import { store as editPostStore } from '@wordpress/edit-post';
import { useMemo } from '@wordpress/element';

/**
 * Internal dependencies
 */
import { unlock } from '../../lock-unlock';
// The Vite query parameter breaks the linter's import resolution
// eslint-disable-next-line import/no-unresolved
import defaultThemeStyles from './default-theme-styles.scss?inline';
// eslint-disable-next-line import/no-unresolved
import commonStyles from './wp-common-styles.scss?inline';

const { getLayoutStyles } = unlock( blockEditorPrivateApis );

/**
 * Custom hook to retrieve and memoize editor styles.
 *
 * @param {...any} additionalStyles Additional styles to add to the default styles.
 *
 * @todo This should be exported from Core so no reimplementation is needed.
 * @see https://github.com/WordPress/gutenberg/blob/a4d79e85a06e06b9123778e6991ac27b0bbe351d/packages/edit-post/src/components/layout/index.js#L86
 *
 * @return {any[]} An array of editor styles.
 */
export function useEditorStyles( ...additionalStyles ) {
	const { hasThemeStyleSupport, editorSettings } = useSelect( ( select ) => {
		return {
			hasThemeStyleSupport:
				select( editPostStore ).isFeatureActive( 'themeStyles' ),
			editorSettings: select( editorStore ).getEditorSettings(),
		};
	}, [] );

	const addedStyles = additionalStyles.join( '\n' );

	// Compute the default styles.
	return useMemo( () => {
		const presetStyles =
			editorSettings.styles?.filter(
				( style ) =>
					style.__unstableType && style.__unstableType !== 'theme'
			) ?? [];

		const defaultEditorStyles = [
			...( editorSettings?.defaultEditorStyles ?? [] ),
			...presetStyles,
		];

		// Has theme styles if the theme supports them and if some styles were not preset styles (in which case they're theme styles).
		const hasThemeStyles =
			hasThemeStyleSupport &&
			presetStyles.length !== ( editorSettings.styles?.length ?? 0 );

		// If theme styles are not present or displayed, ensure that
		// base layout styles are still present in the editor.
		if ( ! editorSettings.disableLayoutStyles && ! hasThemeStyles ) {
			defaultEditorStyles.push( {
				css: getLayoutStyles( {
					style: {},
					selector: 'body',
					hasBlockGapSupport: false,
					hasFallbackGapSupport: true,
					fallbackGapValue: '0.5em',
				} ),
			} );
		}

		// Add sensible default styles if theme styles are not present.
		if ( ! hasThemeStyles ) {
			defaultEditorStyles.push( {
				css: defaultThemeStyles,
			} );
		}

		const baseStyles = hasThemeStyles
			? editorSettings.styles ?? []
			: defaultEditorStyles;

		if ( addedStyles ) {
			return [ ...baseStyles, { css: addedStyles } ];
		}

		// `commonStyles` represent manually added notable styles that are missing.
		// The styles likely absent due to them being injected by the WP Admin
		// context.
		return [ { css: commonStyles }, ...baseStyles ];
	}, [
		editorSettings.defaultEditorStyles,
		editorSettings.disableLayoutStyles,
		editorSettings.styles,
		hasThemeStyleSupport,
		addedStyles,
	] );
}
