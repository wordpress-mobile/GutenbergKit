/**
 * WordPress dependencies
 */
import { ErrorBoundary, AutosaveMonitor } from '@wordpress/editor';
import { SnackbarNotices } from '@wordpress/notices';
import { SlotFillProvider } from '@wordpress/components';

/**
 * Internal dependencies
 */
import Editor from '../editor';
import { onEditorContentChanged } from '../../utils/bridge';
import EditorLoadNotice from '../editor-load-notice';
import OfflineIndicator from '../offline-indicator';
import PopoverSlots from '../popover-slots';
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
			{ /* Share a single slot-fill registry between the popover slots and
			     the editor's popovers. `BlockEditorProvider` otherwise creates
			     its own registry, leaving the slots below unreachable and
			     sending popovers to Gutenberg's fallback container instead. */ }
			<SlotFillProvider>
				{ /* Rendered before the editor so the slots exist by the time
				     popovers look for them. */ }
				<PopoverSlots />
				<OfflineIndicator />
				<AutosaveMonitor autosave={ onEditorContentChanged } />
				<Editor { ...editorProps }>
					<SnackbarNotices className="gutenberg-kit-layout__snackbar" />
				</Editor>
				<EditorLoadNotice
					className="gutenberg-kit-layout__load-notice"
					pluginLoadFailed={ pluginLoadFailed }
				/>
			</SlotFillProvider>
		</ErrorBoundary>
	);
}
