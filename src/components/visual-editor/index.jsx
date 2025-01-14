/**
 * External dependencies
 */
import clsx from 'clsx';

/**
 * WordPress dependencies
 */
import { useRef, useMemo } from '@wordpress/element';
import {
	BlockList,
	privateApis as blockEditorPrivateApis,
} from '@wordpress/block-editor';
import { Popover } from '@wordpress/components';
import {
	store as editorStore,
	mediaUpload,
	EditorSnackbars,
	PostTitle,
	privateApis as editorPrivateApis,
} from '@wordpress/editor';
import { useSelect } from '@wordpress/data';
import { store as coreStore, useEntityBlockEditor } from '@wordpress/core-data';
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
import { useEditorStyles } from '../../hooks/use-editor-styles';
import { unlock } from '../../lock-unlock';
import { useMediaUpload } from '../../hooks/use-media-upload';
import { useHostBridge } from './use-host-bridge';
import { useEditorSetup } from './use-editor-setup';

/**
 * @typedef {import('../utils/bridge').Post} Post
 */

const { useBlockEditorSettings } = unlock(editorPrivateApis);
const {
	ExperimentalBlockEditorProvider: BlockEditorProvider,
	ExperimentalBlockCanvas: BlockCanvas,
} = unlock(blockEditorPrivateApis);

/**
 * Editor component for managing and editing post content.
 *
 * @param {Object} props      Component props.
 * @param {Post}   props.post Post object containing post details.
 *
 * @return {JSX.Element} The rendered Editor component.
 */
function VisualEditor({ post }) {
	const editorPostTitleRef = useRef();
	useHostBridge(post);
	useEditorSetup(post);

	const { isEditorReady } = useSelect((select) => {
		const { __unstableIsEditorReady } = select(editorStore);
		return {
			isEditorReady: __unstableIsEditorReady(),
		};
	}, []);

	const {
		blockPatterns,
		editorSettings,
		hasUploadPermissions,
		reusableBlocks,
	} = useSelect(
		(select) => {
			const { getEntityRecord, getEntityRecords } = select(coreStore);
			const { getEditorSettings } = select(editorStore);
			const user = getEntityRecord('root', 'user', post.author);

			return {
				editorSettings: getEditorSettings(),
				blockPatterns: select(coreStore).getBlockPatterns(),
				hasUploadPermissions: user?.capabilities?.upload_files ?? true,
				reusableBlocks: getEntityRecords('postType', 'wp_block'),
			};
		},
		[post.author]
	);

	const [postBlocks, onInput, onChange] = useEntityBlockEditor(
		'postType',
		post.type,
		{ id: post.id }
	);

	const blockEditorSettings = useBlockEditorSettings(
		editorSettings,
		post.type,
		post.id,
		'visual'
	);

	const settings = useMemo(
		() => ({
			...blockEditorSettings,
			hasFixedToolbar: true,
			mediaUpload: hasUploadPermissions ? mediaUpload : undefined,
			__experimentalReusableBlocks: reusableBlocks,
			__experimentalBlockPatterns: blockPatterns,
		}),
		[
			blockEditorSettings,
			blockPatterns,
			hasUploadPermissions,
			reusableBlocks,
		]
	);

	const styles = useEditorStyles();
	useMediaUpload();

	const useRootPaddingAwareAlignments =
		settings.themeStyles &&
		settings.__experimentalFeatures?.useRootPaddingAwareAlignments;

	const editorClasses = clsx('gutenberg-kit-editor', {
		'has-root-padding': !useRootPaddingAwareAlignments,
	});
	const titleClasses = clsx('editor-visual-editor__post-title-wrapper', {
		'has-global-padding': useRootPaddingAwareAlignments,
	});
	const blockListClasses = clsx({
		'has-global-padding': useRootPaddingAwareAlignments,
	});

	return (
		<div className={editorClasses}>
			<BlockEditorProvider
				value={postBlocks}
				onInput={onInput}
				onChange={onChange}
				settings={settings}
				useSubRegistry={false}
			>
				<BlockCanvas shouldIframe={false} height="100%" styles={styles}>
					<div className={titleClasses}>
						{isEditorReady && (
							<PostTitle ref={editorPostTitleRef} />
						)}
					</div>
					<BlockList className={blockListClasses} />
				</BlockCanvas>
				{isEditorReady && (
					<EditorToolbar className="gutenberg-kit-editor__toolbar" />
				)}

				<Popover.Slot />
				<EditorSnackbars />
			</BlockEditorProvider>
		</div>
	);
}

export default VisualEditor;
