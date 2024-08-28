/**
 * WordPress dependencies
 */
import { useEffect, useRef, useState } from '@wordpress/element';
import {
	BlockList,
	privateApis as blockEditorPrivateApis,
	store as blockEditorStore,
} from '@wordpress/block-editor';
import { Popover } from '@wordpress/components';
import { getBlockTypes, unregisterBlockType } from '@wordpress/blocks';
import { registerCoreBlocks } from '@wordpress/block-library';
import { parse, serialize } from '@wordpress/blocks';
import {
	store as editorStore,
	mediaUpload,
	EditorSnackbars,
	PostTitle,
	privateApis as editorPrivateApis,
} from '@wordpress/editor';
import { useDispatch, useSelect } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';
import { __dangerousOptInToUnstableAPIsOnlyForCoreModules } from '@wordpress/private-apis';

// Default styles that are needed for the editor.
import '@wordpress/components/build-style/style.css';
import '@wordpress/block-editor/build-style/style.css';
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
import { editorLoaded, onBlocksChanged } from '../misc/Helpers';
// import CodeEditor from './CodeEditor';

// Current editor (assumes can be only one instance).
let editor = {};

const POST_MOCK = {
	type: 'post',
};

// eslint-disable-next-line react-refresh/only-export-components
export const { lock, unlock } =
	__dangerousOptInToUnstableAPIsOnlyForCoreModules(
		'I acknowledge private features are not for use in themes or plugins and doing so will break in the next version of WordPress.',
		'@wordpress/editor'
	);

const { useBlockEditorSettings } = unlock(editorPrivateApis);
const {
	ExperimentalBlockEditorProvider: BlockEditorProvider,
	ExperimentalBlockCanvas: BlockCanvas,
} = unlock(blockEditorPrivateApis);

function Editor({ post = POST_MOCK }) {
	const [blocks, setBlocks] = useState([]);
	const [registeredBlocks] = useState([]);
	const [_isCodeEditorEnabled, setCodeEditorEnabled] = useState(false);
	const titleRef = useRef();
	const { setupEditor } = useDispatch(editorStore);

	useEffect(() => {
		window.editor = editor;
		setupEditor(post, [], {});
		registerCoreBlocks();

		editorLoaded();

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
		reusableBlocks,
	} = useSelect((select) => {
		const { getEntityRecord, getEntityRecords } = select(coreStore);
		const { getSettings } = select(blockEditorStore);
		const user = getEntityRecord('root', 'user', post.author);
		return {
			blockPatterns: select(coreStore).getBlockPatterns(),
			editorSettings: getSettings(),
			hasUploadPermissions: user?.capabilities?.upload_files ?? true,
			reusableBlocks: getEntityRecords('postType', 'wp_block'),
		};
	}, []);

	function didChangeBlocks(blocks) {
		setBlocks(blocks);

		// TODO: this doesn't include everything
		const isEmpty =
			blocks.length === 0 ||
			(blocks[0].name == 'core/paragraph' &&
				blocks[0].attributes.content.trim() === '');
		onBlocksChanged(isEmpty);
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

	const blockEditorSettings = useBlockEditorSettings(
		editorSettings,
		post.type,
		post?.id,
		'visual'
	);

	const settings = {
		...blockEditorSettings,
		hasFixedToolbar: true,
		mediaUpload: hasUploadPermissions ? mediaUpload : undefined,
		__experimentalReusableBlocks: reusableBlocks,
		__experimentalBlockPatterns: blockPatterns,
	};

	// if (isCodeEditorEnabled) {
	//     return <CodeEditor value={serialize(blocks)} />;
	// }

	return (
		<div className="editor__container">
			<BlockEditorProvider
				value={blocks}
				onInput={didChangeBlocks}
				onChange={didChangeBlocks}
				settings={settings}
			>
				<BlockCanvas
					shouldIframe={false}
					height="auto"
					styles={settings.styles}
				>
					<div className="editor-visual-editor__post-title-wrapper">
						<PostTitle ref={titleRef} />
					</div>
					<BlockList />
				</BlockCanvas>
				<EditorToolbar registeredBlocks={registeredBlocks} />

				<Popover.Slot />
				<EditorSnackbars />
			</BlockEditorProvider>
		</div>
	);
}

export default Editor;
