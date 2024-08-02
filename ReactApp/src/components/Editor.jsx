// Default styles that are needed for the editor.
import '@wordpress/components/build-style/style.css';
import '@wordpress/block-editor/build-style/style.css';

// Default styles that are needed for the core blocks.
import '@wordpress/block-library/build-style/style.css';
import '@wordpress/block-library/build-style/editor.css';
import '@wordpress/block-library/build-style/theme.css';

// Registers standard formatting options for RichText.
import '@wordpress/format-library/build-style/style.css';

// Internal imports
import EditorToolbar from './EditorToolbar';
import { postMessage } from '../misc/Helpers';
// import CodeEditor from './CodeEditor';

// WordPress
const { useEffect, useState } = window.wp.element;
const {
	BlockEditorKeyboardShortcuts,
	BlockEditorProvider,
	BlockList,
	BlockTools,
	WritingFlow,
	ObserveTyping,
} = window.wp.blockEditor;
const { Popover } = window.wp.components;
const { getBlockTypes, unregisterBlockType } = window.wp.blocks;
const { registerCoreBlocks } = window.wp.blockLibrary;
const { parse, serialize, registerBlockType } = window.wp.blocks;

// Current editor (assumes can be only one instance).
let editor = {};

function Editor() {
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
				if (block.name.startsWith('core/')) {
					unregisterBlockType(block.name);
				}
			});
		};
	}, []);

	const settings = {
		hasFixedToolbar: true,
		bodyPlaceholder: 'Hello!',
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
