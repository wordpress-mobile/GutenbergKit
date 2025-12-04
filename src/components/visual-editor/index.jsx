/**
 * External dependencies
 */
import clsx from 'clsx';

/**
 * WordPress dependencies
 */
import { useRef } from '@wordpress/element';
import {
	BlockList,
	privateApis as blockEditorPrivateApis,
	store as blockEditorStore,
} from '@wordpress/block-editor';
import { store as editorStore, PostTitle } from '@wordpress/editor';
import { useSelect } from '@wordpress/data';
import { store as editPostStore } from '@wordpress/edit-post';
import '@wordpress/format-library';
// Base styles for the content within the block canvas iframe.
import blockEditorContentStyles from '@wordpress/block-editor/build-style/content.css?inline';
import blocksStyles from '@wordpress/block-library/build-style/style.css?inline';
import blocksEditorStyles from '@wordpress/block-library/build-style/editor.css?inline';
import blocksThemeStyles from '@wordpress/block-library/build-style/theme.css?inline';

/**
 * Internal dependencies
 */
import './style.scss';
import EditorToolbar from '../editor-toolbar';
import { useEditorStyles } from './use-editor-styles';
import { unlock } from '../../lock-unlock';
import DefaultBlockAppender from '../default-block-appender';
import { useEditorVisible } from './use-editor-visible';
import defaultThemeStyles from './default-theme-styles.scss?inline';
import commonStyles from './wp-common-styles.scss?inline';

const {
	ExperimentalBlockCanvas: BlockCanvas,
	LayoutStyle,
	useLayoutClasses,
	useLayoutStyles,
} = unlock( blockEditorPrivateApis );

// Add some styles for alignwide/alignfull Post Content and its children.
const alignCSS = `.is-root-container.alignwide { max-width: var(--wp--style--global--wide-size); margin-left: auto; margin-right: auto;}
		.is-root-container.alignwide:where(.is-layout-flow) > :not(.alignleft):not(.alignright) { max-width: var(--wp--style--global--wide-size);}
		.is-root-container.alignfull { max-width: none; margin-left: auto; margin-right: auto;}
		.is-root-container.alignfull:where(.is-layout-flow) > :not(.alignleft):not(.alignright) { max-width: none;}`;

/**
 * Editor component for managing and editing post content.
 *
 * @param {Object}  props           Component props.
 * @param {boolean} props.hideTitle Whether to hide the title input.
 *
 * @return {JSX.Element} The rendered Editor component.
 */
function VisualEditor( { hideTitle } ) {
	const editorPostTitleRef = useRef();
	const editorVisibleRef = useEditorVisible();

	const {
		renderingMode,
		hasThemeStyles,
		themeHasDisabledLayoutStyles,
		themeSupportsLayout,
		hasRootPaddingAwareAlignments,
	} = useSelect( ( select ) => {
		const { getRenderingMode } = select( editorStore );
		const _renderingMode = getRenderingMode();
		const { getSettings } = unlock( select( blockEditorStore ) );
		const _settings = getSettings();
		// Implies editor settings provided theme styles via the REST API.
		const settingsHasStyles = _settings.styles?.length > 0;

		return {
			renderingMode: _renderingMode,
			hasThemeStyles:
				select( editPostStore ).isFeatureActive( 'themeStyles' ) &&
				settingsHasStyles,
			themeSupportsLayout: _settings.supportsLayout,
			themeHasDisabledLayoutStyles: _settings.disableLayoutStyles,
			hasRootPaddingAwareAlignments:
				_settings.__experimentalFeatures?.useRootPaddingAwareAlignments,
		};
	}, [] );

	const styles = useEditorStyles(
		// `commonStyles` represent manually added notable styles that are missing.
		// The styles likely absent due to them being injected by the WP Admin
		// context.
		commonStyles,
		// Add sensible default styles if theme styles are not present.
		hasThemeStyles ? '' : defaultThemeStyles,
		blockEditorContentStyles,
		blocksStyles,
		blocksEditorStyles,
		blocksThemeStyles
	);

	const editorClasses = clsx( 'gutenberg-kit-visual-editor', {
		'has-root-padding': ! hasThemeStyles || ! hasRootPaddingAwareAlignments,
	} );

	const titleClasses = clsx(
		'gutenberg-kit-visual-editor__post-title-wrapper',
		'editor-visual-editor__post-title-wrapper',
		{
			'has-global-padding':
				hasThemeStyles && hasRootPaddingAwareAlignments,
		}
	);

	// An opinionated default, as we currently cannot retrievew the post content
	// attributes from the REST API, as it does not include the current post
	// context.
	const postContentAttributes = {
		align: 'full',
		layout: { type: 'constrained' },
	};
	const { layout = {}, align = '' } = postContentAttributes;
	const postContentLayoutClasses = useLayoutClasses(
		postContentAttributes,
		'core/post-content'
	);
	const postContentLayoutStyles = useLayoutStyles(
		postContentAttributes,
		'core/post-content',
		'.block-editor-block-list__layout.is-root-container'
	);
	const blockListClasses = clsx(
		themeSupportsLayout && postContentLayoutClasses,
		align && `align${ align }`,
		{
			'is-layout-flow': ! themeSupportsLayout,
			'has-global-padding':
				hasThemeStyles && hasRootPaddingAwareAlignments,
		}
	);

	return (
		<div className={ editorClasses } ref={ editorVisibleRef }>
			<BlockCanvas shouldIframe={ false } height="100%" styles={ styles }>
				{ themeSupportsLayout &&
					! themeHasDisabledLayoutStyles &&
					renderingMode === 'post-only' && (
						<>
							<LayoutStyle
								selector=".editor-visual-editor__post-title-wrapper"
								layout={ layout }
							/>
							<LayoutStyle
								selector=".block-editor-block-list__layout.is-root-container"
								layout={ layout }
							/>
							{ align && <LayoutStyle css={ alignCSS } /> }
							{ postContentLayoutStyles && (
								<LayoutStyle
									layout={ layout }
									css={ postContentLayoutStyles }
								/>
							) }
						</>
					) }
				{ ! hideTitle && (
					<div className={ titleClasses }>
						<PostTitle ref={ editorPostTitleRef } />
					</div>
				) }
				<BlockList className={ blockListClasses } layout={ layout } />
				<DefaultBlockAppender />
			</BlockCanvas>

			<EditorToolbar className="gutenberg-kit-visual-editor__toolbar" />
		</div>
	);
}

export default VisualEditor;
