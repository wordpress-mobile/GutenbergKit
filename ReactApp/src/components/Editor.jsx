/* eslint-disable react/prop-types */
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
import { store as coreStore, useEntityBlockEditor } from '@wordpress/core-data';
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

// eslint-disable-next-line react-refresh/only-export-components
export const { lock, unlock } =
	__dangerousOptInToUnstableAPIsOnlyForCoreModules(
		'I acknowledge private features are not for use in themes or plugins and doing so will break in the next version of WordPress.',
		'@wordpress/editor'
	);

const postTypeEntities = [
	{ name: 'post', baseURL: '/wp/v2/posts' },
	{ name: 'page', baseURL: '/wp/v2/pages' },
	{ name: 'attachment', baseURL: '/wp/v2/media' },
	{ name: 'wp_block', baseURL: '/wp/v2/blocks' },
].map((postTypeEntity) => ({
	kind: 'postType',
	...postTypeEntity,
	transientEdits: {
		blocks: true,
		selection: true,
	},
	mergedEdits: {
		meta: true,
	},
	rawAttributes: ['title', 'excerpt', 'content'],
}));

const { useBlockEditorSettings } = unlock(editorPrivateApis);
const {
	ExperimentalBlockEditorProvider: BlockEditorProvider,
	ExperimentalBlockCanvas: BlockCanvas,
} = unlock(blockEditorPrivateApis);

function Editor({ post }) {
	const [blocks, setBlocks] = useState([]);
	const [registeredBlocks] = useState([]);
	const [_isCodeEditorEnabled, setCodeEditorEnabled] = useState(false);
	const titleRef = useRef();
	const { addEntities, receiveEntityRecords } = useDispatch(coreStore);
	const { setupEditor } = useDispatch(editorStore);

	useEffect(() => {
		window.editor = editor;
		addEntities(postTypeEntities);
		receiveEntityRecords('postType', post.type, post);

		setupEditor(post, [], []);
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
		hasPostLoaded,
	} = useSelect((select) => {
		const { hasFinishedResolution, getEntityRecord, getEntityRecords } =
			select(coreStore);
		const { getSettings } = select(blockEditorStore);
		const user = getEntityRecord('root', 'user', post.author);
		return {
			hasPostLoaded: hasFinishedResolution('getEntityRecord', [
				'postType',
				post.type,
				post.id,
			]),
			blockPatterns: select(coreStore).getBlockPatterns(),
			editorSettings: getSettings(),
			hasUploadPermissions: user?.capabilities?.upload_files ?? true,
			reusableBlocks: getEntityRecords('postType', 'wp_block'),
		};
	}, []);

	const [postBlocks, onInput, onChange] = useEntityBlockEditor(
		'postType',
		post.type,
		{
			id: post.id,
		}
	);

	// eslint-disable-next-line no-unused-vars
	function didChangeBlocks(blocks) {
		// setBlocks(blocks);
		// // TODO: this doesn't include everything
		// const isEmpty =
		// 	blocks.length === 0 ||
		// 	(blocks[0].name == 'core/paragraph' &&
		// 		blocks[0].attributes.content.trim() === '');
		// onBlocksChanged(isEmpty);
	}

	function onBlockEditorInput(blocks, options) {
		onInput(blocks, options);
		didChangeBlocks(blocks);
	}

	function onBlockEditorChange(blocks, options) {
		onChange(blocks, options);
		didChangeBlocks(blocks);
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
		post.id,
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
		hasPostLoaded && (
			<div className="editor__container">
				<BlockEditorProvider
					value={postBlocks}
					onInput={onBlockEditorInput}
					onChange={onBlockEditorChange}
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
		)
	);
}

export default Editor;
