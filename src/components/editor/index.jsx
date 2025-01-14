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

/**
 * @typedef {import('../utils/bridge').Post} Post
 */

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

	return (
		<div className="gutenberg-kit-editor-interface">
			<EditorLoadNotice className="gutenberg-kit-editor-interface__load-notice" />
			<VisualEditor post={post} />
		</div>
	);
}
