import { useEffect, useRef, useState } from 'react';

// WordPress
import {
	BlockEditorKeyboardShortcuts,
	BlockEditorProvider,
	BlockList,
	BlockTools,
	WritingFlow,
	ObserveTyping,
} from '@wordpress/block-editor';
import { Popover } from '@wordpress/components';
import { getBlockTypes, unregisterBlockType } from '@wordpress/blocks';
import { registerCoreBlocks } from '@wordpress/block-library';
import { parse, serialize, registerBlockType } from '@wordpress/blocks';
import {
	store as editorStore,
	mediaUpload,
	PostTitle,
} from '@wordpress/editor';
import { useDispatch, useSelect } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';

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

const POST_MOCK = {
	id: 1,
	type: 'post',
	author: 1,
};

function Editor({ post = POST_MOCK }) {
	const [blocks, setBlocks] = useState([]);
	const [registeredBlocks, setRegisteredBlocks] = useState([]);
	const [isCodeEditorEnabled, setCodeEditorEnabled] = useState(false);
	const titleRef = useRef();
	const { setupEditor } = useDispatch(editorStore);

	useEffect(() => {
		setupEditor(post, [], {});
	}, []);

	const { hasUploadPermissions } = useSelect((select) => {
		const { getEntityRecord } = select(coreStore);
		const user = getEntityRecord('root', 'user', post.author);

		return {
			hasUploadPermissions: user?.capabilities?.upload_files ?? true,
		};
	}, []);

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
		mediaUpload: hasUploadPermissions ? mediaUpload : undefined,
	};

	// if (isCodeEditorEnabled) {
	//     return <CodeEditor value={serialize(blocks)} />;
	// }

	return (
		<BlockEditorProvider
			value={blocks}
			onInput={didChangeBlocks}
			onChange={didChangeBlocks}
			settings={settings}
		>
			<div className="editor-visual-editor__post-title-wrapper">
				<PostTitle ref={titleRef} />
			</div>
			<BlockTools>
				<div className="editor-styles-wrapper">
					<BlockEditorKeyboardShortcuts.Register />
					<WritingFlow>
						<ObserveTyping>
							<BlockList />
							<EditorToolbar
								registeredBlocks={registeredBlocks}
							/>{' '}
							{/* not sure if optimal placement */}
						</ObserveTyping>
					</WritingFlow>
				</div>
			</BlockTools>
			<Popover.Slot />
		</BlockEditorProvider>
	);
}

export default Editor;
