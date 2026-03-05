/**
 * WordPress dependencies
 */
import {
	EditorSnackbars,
	ErrorBoundary,
	AutosaveMonitor,
} from '@wordpress/editor';

/**
 * Internal dependencies
 */
import Editor from '../editor';
import { onEditorContentChanged } from '../../utils/bridge';
import EditorLoadNotice from '../editor-load-notice';
import './style.scss';

/**
 * Top-level layout, including the Editor component wrapped in an ErrorBoundary.
 *
 * @param {Object}  props                  The settings passed along to the Editor component.
 * @param {boolean} props.pluginLoadFailed Whether plugin loading failed.
 *
 * @return {Element} The rendered Layout component.
 */
export default function Layout( props ) {
	const { pluginLoadFailed, ...editorProps } = props;

	return (
		<ErrorBoundary canCopyContent>
			<AutosaveMonitor autosave={ onEditorContentChanged } />
			<Editor { ...editorProps }>
				<EditorSnackbars />
			</Editor>
			<EditorLoadNotice
				className="gutenberg-kit-layout__load-notice"
				pluginLoadFailed={ pluginLoadFailed }
			/>
		</ErrorBoundary>
	);
}
