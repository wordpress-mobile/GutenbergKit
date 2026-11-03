import { AutosaveMonitor } from '@wordpress/editor';
import { SnackbarNotices } from '@wordpress/notices';
import { SlotFillProvider } from '@wordpress/components';
import Editor from '../editor';
import EditorErrorBoundary from '../editor-error-boundary';
import { onEditorContentChanged } from '../../utils/bridge';
import { S4CrashTrigger, S4Panel } from '../../utils/spike-save-failures';
import EditorLoadNotice from '../editor-load-notice';
import OfflineIndicator from '../offline-indicator';
import PopoverSlots from '../popover-slots';
import './style.scss';

/**
 * Top-level layout, including the Editor component wrapped in an error boundary.
 *
 * @param {Object}  props                  The settings passed along to the Editor component.
 * @param {boolean} props.pluginLoadFailed Whether plugin loading failed.
 *
 * @return {Element} The rendered Layout component.
 */
export default function Layout( props ) {
	const { pluginLoadFailed, ...editorProps } = props;

	// SPIKE (S4): the panel sits outside the boundary so it survives a crash.
	return (
		<>
			<S4Panel />
			<EditorErrorBoundary>
				<SlotFillProvider>
					<PopoverSlots />
					<OfflineIndicator />
					<AutosaveMonitor
						interval={ 1 }
						autosave={ onEditorContentChanged }
					/>
					<Editor { ...editorProps }>
						<SnackbarNotices className="gutenberg-kit-layout__snackbar" />
						<S4CrashTrigger />
					</Editor>
					<EditorLoadNotice
						className="gutenberg-kit-layout__load-notice"
						pluginLoadFailed={ pluginLoadFailed }
					/>
				</SlotFillProvider>
			</EditorErrorBoundary>
		</>
	);
}
