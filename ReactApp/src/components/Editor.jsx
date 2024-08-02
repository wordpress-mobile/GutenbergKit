/* eslint-disable react/prop-types */
import { useEffect, useState } from 'react';

// WordPress
import {
	BlockEditorKeyboardShortcuts,
	BlockEditorProvider,
	BlockList,
	BlockTools,
	WritingFlow,
	ObserveTyping,
} from '@wordpress/block-editor';
import { Popover, SlotFillProvider } from '@wordpress/components';
import { getBlockTypes, unregisterBlockType } from '@wordpress/blocks';
import { registerCoreBlocks } from '@wordpress/block-library';
import { parse, serialize, registerBlockType } from '@wordpress/blocks';
import { mediaUpload, store as editorStore } from '@wordpress/editor';
import { useSelect, useDispatch } from '@wordpress/data';
import { store as coreStore, EntityProvider } from '@wordpress/core-data';

// Default styles that are needed for the editor.
import '@wordpress/components/build-style/style.css';
import '@wordpress/block-editor/build-style/style.css';

// Default styles that are needed for the core blocks.
import '@wordpress/block-library/build-style/style.css';
import '@wordpress/block-library/build-style/editor.css';
import '@wordpress/block-library/build-style/theme.css';

// Registers standard formatting options for RichText.
import '@wordpress/format-library';
import '@wordpress/format-library/build-style/style.css';

// Internal imports
import EditorToolbar from './EditorToolbar';
import { postMessage } from '../misc/Helpers';
// import CodeEditor from './CodeEditor';

// Current editor (assumes can be only one instance).
let editor = {};

function Editor() {
	const postType = 'post';
	const postId = 5;
	const author = 1;
	const { hasUploadPermissions, reusableBlocks } = useSelect(
		(select) => {
			const { getEntityRecord, getEntityRecords } = select(coreStore);
			const user = getEntityRecord('root', 'user', author);

			return {
				reusableBlocks: getEntityRecords('postType', 'wp_block', {
					per_page: 100,
				}),
				hasUploadPermissions: user?.capabilities?.upload_files ?? true,
			};
		},
		[postType, postId]
	);

	const { setEditedPost } = useDispatch(editorStore);

	useEffect(() => {
		setEditedPost(postType, postId);
	}, [postType, postId, setEditedPost]);

	const post = {
		id: postId,
		title: {
			raw: '',
		},
		featured_media: undefined,
		content: {
			raw: '',
		},
		type: postType,
		status: 'draft',
		meta: [],
	};

	return (
		<EditorComponent
			post={post}
			hasUploadPermissions={hasUploadPermissions}
			reusableBlocks={reusableBlocks}
		/>
	);
}

function EditorComponent({ post, hasUploadPermissions, reusableBlocks }) {
	const [blocks, setBlocks] = useState([]);
	const [registeredBlocks, setRegisteredBlocks] = useState([]);
	const [isCodeEditorEnabled, setCodeEditorEnabled] = useState(false);

	function didChangeBlocks(blocks) {
		setBlocks(blocks);

		// TODO: this doesn't include everything
		const isEmpty =
			blocks.length === 0 ||
			(blocks[0].name == 'core/paragraph' &&
				blocks[0].attributes.content.trim() === '');
		postMessage('onBlocksChanged', { isEmpty: isEmpty });
	}

	editor.setContent = (content) => {
		setBlocks(parse(content));
	};

	editor.setInitialContent = (content) => {
		const blocks = parse(content);
		didChangeBlocks(blocks); // TODO: redesign this
		return serialize(blocks); // It's used for tracking changes
	};

	editor.getContent = () => serialize(blocks);

	editor.setCodeEditorEnabled = (enabled) => setCodeEditorEnabled(enabled);

	editor.registerBlocks = (blockTypes) => {
		// TODO: uncomment when the custom picker is ready (blocker: can't insert blocks)
		// setRegisteredBlocks(blockTypes);
		// TODO: uncomment to enable custom block registration
		// for (const blockType of blockTypes) {
		//     registerBlockType(blockType.name, blockType);
		// }
	};

	useEffect(() => {
		window.editor = editor;
		registerCoreBlocks();
		postMessage('onEditorLoaded');

		return () => {
			window.editor = {};
			getBlockTypes().forEach((block) => {
				unregisterBlockType(block.name);
			});
		};
	}, []);

	const settings = {
		hasFixedToolbar: true,
		bodyPlaceholder: 'Hello!',
		titlePlaceholder: 'Add title',
		mediaUpload: hasUploadPermissions ? mediaUpload : undefined,
		__experimentalReusableBlocks: reusableBlocks,
	};

	// if (isCodeEditorEnabled) {
	//     return <CodeEditor value={serialize(blocks)} />;
	// }

	return (
		<SlotFillProvider>
			<EntityProvider kind="root" type="site">
				<EntityProvider kind="postType" type={post.type} id={post.id}>
					<BlockEditorProvider
						value={blocks}
						onInput={didChangeBlocks}
						onChange={didChangeBlocks}
						settings={settings}
					>
						<BlockTools>
							<div className="editor-styles-wrapper">
								<BlockEditorKeyboardShortcuts.Register />
								<WritingFlow>
									<ObserveTyping>
										<BlockList />
										<EditorToolbar
											registeredBlocks={registeredBlocks}
										/>
									</ObserveTyping>
								</WritingFlow>
							</div>
						</BlockTools>
						<Popover.Slot />
					</BlockEditorProvider>
				</EntityProvider>
			</EntityProvider>
		</SlotFillProvider>
	);
}

export default Editor;
