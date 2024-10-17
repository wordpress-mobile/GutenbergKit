/* eslint-disable react/prop-types */
/**
 * WordPress dependencies
 */
import { useEffect, useRef, useState, useMemo } from '@wordpress/element';
import {
	BlockList,
	privateApis as blockEditorPrivateApis,
} from '@wordpress/block-editor';
import { Popover } from '@wordpress/components';
import {
	getBlockTypes,
	unregisterBlockType,
	getBlockType,
	createBlock,
} from '@wordpress/blocks';
import { registerCoreBlocks } from '@wordpress/block-library';
import {
	store as editorStore,
	mediaUpload,
	EditorProvider,
	EditorSnackbars,
	PostTitle,
} from '@wordpress/editor';
import { store as blockEditorStore } from '@wordpress/block-editor';
import { useDispatch, useSelect, subscribe } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';
import { store as noticesStore } from '@wordpress/notices';
import { __ } from '@wordpress/i18n';

// Default styles that are needed for the editor.
import '@wordpress/components/build-style/style.css';
import '@wordpress/block-editor/build-style/default-editor-styles.css';
import '@wordpress/block-editor/build-style/style.css';
import '@wordpress/block-editor/build-style/content.css';
import '@wordpress/editor/build-style/style.css';

// Default styles that are needed for the core blocks.
import '@wordpress/block-library/build-style/style.css';
import '@wordpress/block-library/build-style/editor.css';
import '@wordpress/block-library/build-style/theme.css';

// Registers standard formatting options for RichText.
import '@wordpress/format-library';
import '@wordpress/format-library/build-style/style.css';

// Internal imports
import EditorToolbar from './EditorToolbar';
import {
	blurEditor,
	editorLoaded,
	onEditorContentChanged,
} from '../misc/Helpers';
import { postTypeEntities } from '../misc/post-type-entities';
import { useEditorStyles } from './hooks/use-editor-styles';
import { unlock } from './lock-unlock';
// import CodeEditor from './CodeEditor';

// Current editor (assumes can be only one instance).
let editor = {};

const { ExperimentalBlockCanvas: BlockCanvas } = unlock(blockEditorPrivateApis);

function Editor({ post }) {
	const [_isCodeEditorEnabled, setCodeEditorEnabled] = useState(false);
	const editorPostTitleRef = useRef();
	const postTitleRef = useRef(post.title);
	const postContentRef = useRef(post.content);
	const { addEntities, editEntityRecord, receiveEntityRecords } =
		useDispatch(coreStore);
	const { setEditedPost } = useDispatch(editorStore);
	const { getEditedPostAttribute, getEditedPostContent } =
		useSelect(editorStore);
	const { createErrorNotice } = useDispatch(noticesStore);
	const { insertBlock } = useDispatch(blockEditorStore);

	useEffect(() => {
		window.editor = editor;
		addEntities(postTypeEntities);
		receiveEntityRecords('postType', post.type, post);

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
		currentPost,
		hasLoadedPost,
		hasUploadPermissions,
		reusableBlocks,
	} = useSelect((select) => {
		const { getEntityRecord, getEntityRecords, hasFinishedResolution } =
			select(coreStore);
		const user = getEntityRecord('root', 'user', post.author);
		const currentPost = getEntityRecord('postType', post.type, post.id);
		const hasLoadedPost = post?.id
			? hasFinishedResolution('getEntityRecord', [
					'postType',
					post.type,
					post.id,
				])
			: true;

		return {
			blockPatterns: select(coreStore).getBlockPatterns(),
			currentPost,
			hasLoadedPost,
			hasUploadPermissions: user?.capabilities?.upload_files ?? true,
			reusableBlocks: getEntityRecords('postType', 'wp_block'),
		};
	}, []);

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

	editor.setCodeEditorEnabled = (enabled) => setCodeEditorEnabled(enabled);

	editor.appendMedia = (media = []) => {
		// TODO: Handle multiple media items.
		const item = media[0];
		let mediaType;
		switch (item.mimetype) {
			case 'image/jpeg':
			case 'image/png':
			case 'image/gif':
				mediaType = 'image';
				break;
			case 'video/mp4':
				mediaType = 'video';
				break;
			default:
				createErrorNotice(
					__('File type not supported as a media file.')
				);
				return;
		}
		const blockName = 'core/' + mediaType;
		const blockType = getBlockType(blockName);

		if (blockType && blockType?.name) {
			const newBlock = createBlock(blockType.name, {
				id: item.Id,
				[mediaType === 'image' ? 'url' : 'src']: item.url,
			});

			// const indexAfterSelected = this.props.selectedBlockIndex + 1;
			// const insertionIndex =
			// 	indexAfterSelected || this.props.blockCount || 0;

			insertBlock(newBlock, 0);
		} else {
			createErrorNotice(__('File type not supported as a media file.'));
		}
	};

	const settings = useMemo(
		() => ({
			hasFixedToolbar: true,
			mediaUpload: hasUploadPermissions ? mediaUpload : undefined,
			__experimentalReusableBlocks: reusableBlocks,
			__experimentalBlockPatterns: blockPatterns,
		}),
		[blockPatterns, hasUploadPermissions, reusableBlocks]
	);

	const styles = useEditorStyles();

	// if (isCodeEditorEnabled) {
	//     return <CodeEditor value={serialize(blocks)} />;
	// }

	return (
		hasLoadedPost && (
			<div className="editor__container">
				<EditorProvider
					post={currentPost}
					settings={settings}
					useSubRegistry={false}
				>
					<BlockCanvas
						shouldIframe={false}
						height="auto"
						styles={styles}
					>
						<div className="editor-visual-editor__post-title-wrapper">
							<PostTitle ref={editorPostTitleRef} />
						</div>
						<BlockList />
					</BlockCanvas>
					<EditorToolbar />

					<Popover.Slot />
					<EditorSnackbars />
				</EditorProvider>
			</div>
		)
	);
}

export default Editor;
