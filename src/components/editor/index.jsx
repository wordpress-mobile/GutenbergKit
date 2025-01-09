/**
 * Internal dependencies
 */
import VisualEditor from '../visual-editor';
import EditorLoadNotice from '../editor-load-notice';
import './style.scss';
import { useSyncHistoryControls } from './use-sync-history-controls';

/**
 * Entry component rendering the editor and surrounding UI.
 *
 * @param {Object} props Component props.
 *
 * @return {JSX.Element} The rendered App component.
 */
export default function Editor(props) {
	useSyncHistoryControls();

	return (
		<div className="gutenberg-kit-editor-interface">
			<EditorLoadNotice className="gutenberg-kit-editor-interface__load-notice" />
			<VisualEditor {...props} />
		</div>
	);
}
