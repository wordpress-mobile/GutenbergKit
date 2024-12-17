/**
 * WordPress dependencies
 */
import { useEffect, useRef, useMemo } from '@wordpress/element';
import {
	BlockList,
	privateApis as blockEditorPrivateApis,
} from '@wordpress/block-editor';
import { Popover } from '@wordpress/components';
import { getBlockTypes, unregisterBlockType } from '@wordpress/blocks';
import { registerCoreBlocks } from '@wordpress/block-library';
import {
	store as editorStore,
	mediaUpload,
	EditorSnackbars,
	PostTitle,
	privateApis as editorPrivateApis,
} from '@wordpress/editor';
import { useDispatch, useSelect, subscribe } from '@wordpress/data';
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
import { editorLoaded, onEditorContentChanged } from '../../utils/bridge';
import { postTypeEntities } from '../../utils/post-type-entities';
import { useEditorStyles } from '../../hooks/use-editor-styles';
import { unlock } from '../../lock-unlock';
import { useMediaUpload } from '../../hooks/use-media-upload';

/**
 * @typedef {import('../utils/bridge').Post} Post
 */

// Current editor (assumes can be only one instance).
const editor = {};

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
function Editor({ post }) {
	const postTitleRef = useRef(post.title);
	const postContentRef = useRef(post.content);
	const { addEntities, editEntityRecord, receiveEntityRecords } =
		useDispatch(coreStore);
	const { setEditedPost } = useDispatch(editorStore);
	const { getEditedPostAttribute, getEditedPostContent } =
		useSelect(editorStore);
	const { setupEditor } = useDispatch(editorStore);

	useEffect(() => {
		window.editor = editor;
		addEntities(postTypeEntities);
		receiveEntityRecords('postType', post.type, post);

		setupEditor(post, {});
		registerCoreBlocks();

		editorLoaded();
		// Temp, check why this isn't being called in the provider.
		setEditedPost(post.type, post.id);

		return () => {
			window.editor = {};
			getBlockTypes().forEach((block) => {
				unregisterBlockType(block.name);
			});
		};
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, []);

	const {
		blockPatterns,
		editorSettings,
		hasUploadPermissions,
		isEditorReady,
		reusableBlocks,
	} = useSelect(
		(select) => {
			const { getEntityRecord, getEntityRecords } = select(coreStore);
			const { __unstableIsEditorReady, getEditorSettings } =
				select(editorStore);
			const user = getEntityRecord('root', 'user', post.author);
			const _isEditorReady = post?.id ? __unstableIsEditorReady() : true;

			return {
				isEditorReady: _isEditorReady,
				editorSettings: getEditorSettings(),
				blockPatterns: select(coreStore).getBlockPatterns(),
				hasUploadPermissions: user?.capabilities?.upload_files ?? true,
				reusableBlocks: getEntityRecords('postType', 'wp_block'),
			};
		},
		[post.author, post.id]
	);

	const [postBlocks, onInput, onChange] = useEntityBlockEditor(
		'postType',
		post.type,
		{ id: post.id }
	);

	useEffect(() => {
		return subscribe(() => {
			const { title, content } = editor.getTitleAndContent();
			if (
				title !== postTitleRef.current ||
				content !== postContentRef.current
			) {
				onEditorContentChanged();
				postTitleRef.current = title;
				postContentRef.current = content;
			}
		});
	}, []);

	function editContent(edits) {
		editEntityRecord('postType', post.type, post.id, edits);
	}

	editor.setContent = (content) => {
		editContent({ content: decodeURIComponent(content) });
	};

	editor.setTitle = (title) => {
		editContent({ title: decodeURIComponent(title) });
	};

	editor.getContent = (blurInput = false) => {
		if (blurInput) {
			blurEditor();
		}
		return getEditedPostContent();
	};

	editor.getTitleAndContent = (blurInput = false) => {
		if (blurInput) {
			blurEditor();
		}
		return {
			title: getEditedPostAttribute('title'),
			content: getEditedPostContent(),
		};
	};

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

	return (
		<div className="editor__container">
			<BlockEditorProvider
				value={postBlocks}
				onInput={onInput}
				onChange={onChange}
				settings={settings}
				useSubRegistry={false}
			>
				<BlockCanvas shouldIframe={false} height="auto" styles={styles}>
					<div className="editor-visual-editor__post-title-wrapper">
						{isEditorReady && <PostTitle ref={postTitleRef} />}
					</div>
					<BlockList />
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

export default Editor;

/**
 * Blurs the currently active paragraph element in the document.
 *
 * This function checks if the currently active element is a paragraph (`<p>`).
 * If it is, the function removes focus from that element.
 *
 * @todo Address the disabled eslint rule `@wordpress/no-global-active-element`.
 *
 * @return {void}
 */
function blurEditor() {
	// eslint-disable-next-line @wordpress/no-global-active-element
	const activeElement = document.activeElement;

	if (activeElement && activeElement.tagName === 'P') {
		activeElement.blur();
	}
}
