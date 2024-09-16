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
import { getBlockTypes, unregisterBlockType } from '@wordpress/blocks';
import { registerCoreBlocks } from '@wordpress/block-library';
import { parse, serialize } from '@wordpress/blocks';
import {
	store as editorStore,
	mediaUpload,
	EditorSnackbars,
	PostTitle,
} from '@wordpress/editor';
import { ExperimentalEditorProvider } from '@wordpress/editor/src/components/provider';
import { useDispatch, useSelect } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';

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
import { editorLoaded } from '../misc/Helpers';
import { postTypeEntities } from '../misc/post-type-entities';
import { useEditorStyles } from './hooks/use-editor-styles';
import { unlock } from './lock-unlock';
// import CodeEditor from './CodeEditor';

// Current editor (assumes can be only one instance).
let editor = {};

const { ExperimentalBlockCanvas: BlockCanvas } = unlock(blockEditorPrivateApis);

function Editor({ post }) {
	const [blocks, setBlocks] = useState([]);
	const [_isCodeEditorEnabled, setCodeEditorEnabled] = useState(false);
	const titleRef = useRef();
	const { addEntities, receiveEntityRecords } = useDispatch(coreStore);

	useEffect(() => {
		window.editor = editor;
		addEntities(postTypeEntities);
		receiveEntityRecords('postType', post.type, post);

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
		currentPost,
		editorSettings,
		hasLoadedPost,
		hasUploadPermissions,
		reusableBlocks,
	} = useSelect((select) => {
		const { getEntityRecord, getEntityRecords, hasFinishedResolution } =
			select(coreStore);
		const { getEditorSettings } = select(editorStore);
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
			editorSettings: getEditorSettings(),
			hasLoadedPost,
			hasUploadPermissions: user?.capabilities?.upload_files ?? true,
			reusableBlocks: getEntityRecords('postType', 'wp_block'),
		};
	}, []);

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

	const settings = useMemo(
		() => ({
			...editorSettings,
			hasFixedToolbar: true,
			mediaUpload: hasUploadPermissions ? mediaUpload : undefined,
			__experimentalReusableBlocks: reusableBlocks,
			__experimentalBlockPatterns: blockPatterns,
		}),
		[blockPatterns, editorSettings, hasUploadPermissions, reusableBlocks]
	);

	const styles = useEditorStyles();

	// if (isCodeEditorEnabled) {
	//     return <CodeEditor value={serialize(blocks)} />;
	// }

	return (
		hasLoadedPost && (
			<div className="editor__container">
				<ExperimentalEditorProvider
					post={currentPost}
					settings={settings}
				>
					<BlockCanvas
						shouldIframe={false}
						height="auto"
						styles={styles}
					>
						<div className="editor-visual-editor__post-title-wrapper">
							<PostTitle ref={titleRef} />
						</div>
						<BlockList />
					</BlockCanvas>
					<EditorToolbar />

					<Popover.Slot />
					<EditorSnackbars />
				</ExperimentalEditorProvider>
			</div>
		)
	);
}

export default Editor;
