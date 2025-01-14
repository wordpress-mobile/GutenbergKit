/**
 * WordPress dependencies
 */
import { useEntityBlockEditor } from '@wordpress/core-data';
import { privateApis as blockEditorPrivateApis } from '@wordpress/block-editor';

/**
 * Internal dependencies
 */
import VisualEditor from '../visual-editor';
import EditorLoadNotice from '../editor-load-notice';
import './style.scss';
import { useSyncHistoryControls } from './use-sync-history-controls';
import { useHostBridge } from './use-host-bridge';
import { useEditorSetup } from './use-editor-setup';
import { useMediaUpload } from '../../hooks/use-media-upload';
import { useGBKitSettings } from './use-gbkit-settings';
import { unlock } from '../../lock-unlock';

/**
 * @typedef {import('../utils/bridge').Post} Post
 */
const { ExperimentalBlockEditorProvider: BlockEditorProvider } = unlock(
	blockEditorPrivateApis
);

/**
 * Entry component rendering the editor and surrounding UI.
 *
 * @param {Object} props      Component props.
 * @param {Post}   props.post Post object containing post details.
 *
 * @return {JSX.Element} The rendered App component.
 */
export default function Editor({ post }) {
	useSyncHistoryControls();
	useHostBridge(post);
	useEditorSetup(post);
	useMediaUpload();

	const [postBlocks, onInput, onChange] = useEntityBlockEditor(
		'postType',
		post.type,
		{ id: post.id }
	);

	const settings = useGBKitSettings(post);
	const useRootPaddingAwareAlignments =
		settings.themeStyles &&
		settings.__experimentalFeatures?.useRootPaddingAwareAlignments;

	return (
		<div className="gutenberg-kit-editor-interface">
			<EditorLoadNotice className="gutenberg-kit-editor-interface__load-notice" />
			<BlockEditorProvider
				value={postBlocks}
				onInput={onInput}
				onChange={onChange}
				settings={settings}
				useSubRegistry={false}
			>
				<VisualEditor
					useRootPaddingAwareAlignments={
						useRootPaddingAwareAlignments
					}
				/>
			</BlockEditorProvider>
		</div>
	);
}
