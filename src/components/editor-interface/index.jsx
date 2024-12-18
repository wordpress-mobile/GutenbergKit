/**
 * Internal dependencies
 */
import Editor from '../editor';
import EditorLoadNotice from '../editor-load-notice';
import './style.scss';

/**
 * Entry component rendering the editor and surrounding UI.
 *
 * @param {Object} props Component props.
 *
 * @return {JSX.Element} The rendered App component.
 */
export default function EditorInterface(props) {
	return (
		<div className="gutenberg-kit-editor-interface">
			<EditorLoadNotice className="gutenberg-kit-editor-interface__load-notice" />
			<Editor {...props} />
		</div>
	);
}
