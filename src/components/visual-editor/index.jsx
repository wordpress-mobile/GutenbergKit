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
import { Popover } from '@wordpress/components';
import { store as editorStore, PostTitle } from '@wordpress/editor';
import { useSelect } from '@wordpress/data';
// Default styles that are needed for the editor.
import '@wordpress/components/build-style/style.css';
import '@wordpress/block-editor/build-style/style.css';
// Default styles that are needed for the core blocks.
import '@wordpress/block-library/build-style/style.css';
import '@wordpress/block-library/build-style/editor.css';
import '@wordpress/block-library/build-style/theme.css';
import '@wordpress/format-library';
import '@wordpress/format-library/build-style/style.css';
import '@wordpress/block-editor/build-style/content.css';
import '@wordpress/editor/build-style/style.css';

/**
 * Internal dependencies
 */
import './style.scss';
import EditorToolbar from '../editor-toolbar';
import { useEditorStyles } from './use-editor-styles';
import { unlock } from '../../lock-unlock';
import { getGBKit } from '../../utils/bridge';

const { ExperimentalBlockCanvas: BlockCanvas, useLayoutClasses } = unlock(
	blockEditorPrivateApis
);

/**
 * Editor component for managing and editing post content.
 *
 * @param {Object}  props                               Component props.
 * @param {boolean} props.useRootPaddingAwareAlignments Apply root padding.
 *
 * @return {JSX.Element} The rendered Editor component.
 */
function VisualEditor({ useRootPaddingAwareAlignments }) {
	const editorPostTitleRef = useRef();
	const { settings } = getGBKit();
	const isTitleHidden = settings?.isTitleHidden || false;

	const { isEditorReady, themeSupportsLayout } = useSelect((select) => {
		const { __unstableIsEditorReady } = select(editorStore);
		const { getSettings } = unlock(select(blockEditorStore));
		const _settings = getSettings();

		return {
			themeSupportsLayout: _settings.supportsLayout,
			isEditorReady: __unstableIsEditorReady(),
		};
	}, []);

	const styles = useEditorStyles();

	const editorClasses = clsx('gutenberg-kit-visual-editor', {
		'has-root-padding': !useRootPaddingAwareAlignments,
	});
	const titleClasses = clsx(
		'gutenberg-kit-visual-editor__post-title-wrapper',
		{
			'has-global-padding': useRootPaddingAwareAlignments,
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
	const blockListClasses = clsx(
		themeSupportsLayout && postContentLayoutClasses,
		align && `align${align}`,
		{
			'is-layout-flow': !themeSupportsLayout,
			'has-global-padding': useRootPaddingAwareAlignments,
		}
	);

	return (
		<div className={editorClasses}>
			<BlockCanvas shouldIframe={false} height="100%" styles={styles}>
				{!isTitleHidden && (
					<div className={titleClasses}>
						{isEditorReady && (
							<PostTitle ref={editorPostTitleRef} />
						)}
					</div>
				)}
				<BlockList className={blockListClasses} layout={layout} />
			</BlockCanvas>

			{isEditorReady && (
				<EditorToolbar className="gutenberg-kit-visual-editor__toolbar" />
			)}

			<Popover.Slot />
		</div>
	);
}

export default VisualEditor;
