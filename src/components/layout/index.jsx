import { AutosaveMonitor } from '@wordpress/editor';
import { SnackbarNotices } from '@wordpress/notices';
import { SlotFillProvider } from '@wordpress/components';
import Editor from '../editor';
import EditorErrorBoundary from '../editor-error-boundary';
import { onEditorContentChanged } from '../../utils/bridge';
import EditorLoadNotice from '../editor-load-notice';
import OfflineIndicator from '../offline-indicator';
import PopoverSlots from '../popover-slots';
import { S6Panel } from '../../utils/spike-synced-entities';
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

	// SPIKE (S6): the panel logs writes and lists dirty entities.
	return (
		<EditorErrorBoundary>
			<S6Panel />
			<SlotFillProvider>
				<PopoverSlots />
				<OfflineIndicator />
				<AutosaveMonitor
					interval={ 1 }
					autosave={ onEditorContentChanged }
				/>
				<Editor { ...editorProps }>
					<SnackbarNotices className="gutenberg-kit-layout__snackbar" />
				</Editor>
				<EditorLoadNotice
					className="gutenberg-kit-layout__load-notice"
					pluginLoadFailed={ pluginLoadFailed }
				/>
			</SlotFillProvider>
		</EditorErrorBoundary>
	);
}
