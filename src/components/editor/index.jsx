/**
 * WordPress dependencies
 */
import { useEntityBlockEditor } from '@wordpress/core-data';
import { privateApis as blockEditorPrivateApis } from '@wordpress/block-editor';
import { useSelect } from '@wordpress/data';
import { store as editorStore, ErrorBoundary } from '@wordpress/editor';

/**
 * Internal dependencies
 */
import VisualEditor from '../visual-editor';
import EditorLoadNotice from '../editor-load-notice';
import './style.scss';
import { useSyncHistoryControls } from './use-sync-history-controls';
import { useHostBridge } from './use-host-bridge';
import { useEditorSetup } from './use-editor-setup';
import { useMediaUpload } from './use-media-upload';
import { useGBKitSettings } from './use-gbkit-settings';
import { unlock } from '../../lock-unlock';
import TextEditor from '../text-editor';

/**
 * @typedef {import('../utils/bridge').Post} Post
 */

const { ExperimentalBlockEditorProvider: BlockEditorProvider } = unlock(
	blockEditorPrivateApis
);

/**
 * Entry component rendering the editor and surrounding UI.
 *
 * @param {Object}                               props          Component props.
 * @param {Post}                                 props.post     Post object containing post details.
 * @param {import('@wordpress/element').Element} props.children The children to render in the editor.
 *
 * @return {JSX.Element} The rendered App component.
 */
export default function Editor({ post, children }) {
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

	const { mode, isRichEditingEnabled } = useSelect((select) => {
		const { getEditorSettings, getEditorMode } = select(editorStore);
		const editorSettings = getEditorSettings();
		return {
			mode: getEditorMode(),
			isRichEditingEnabled: editorSettings.richEditingEnabled,
		};
	}, []);

	return (
		<ErrorBoundary>
			<div className="gutenberg-kit-editor-interface">
				<EditorLoadNotice className="gutenberg-kit-editor-interface__load-notice" />
				<BlockEditorProvider
					value={postBlocks}
					onInput={onInput}
					onChange={onChange}
					settings={settings}
					useSubRegistry={false}
				>
					{mode === 'visual' && isRichEditingEnabled && (
						<VisualEditor
							useRootPaddingAwareAlignments={
								useRootPaddingAwareAlignments
							}
						/>
					)}

					{(mode === 'text' || !isRichEditingEnabled) && (
						<TextEditor
							// We should auto-focus the canvas (title) on load.
							// eslint-disable-next-line jsx-a11y/no-autofocus
							autoFocus={true}
						/>
					)}

					{children}
				</BlockEditorProvider>
			</div>
		</ErrorBoundary>
	);
}
