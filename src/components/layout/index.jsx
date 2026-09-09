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
		// `canCopyContent` is deliberately omitted. Its "Copy contents" button
		// reads the post through `getEditedPostContent()` at click time, but the
		// boundary sits above `EditorProvider`, whose unmount clears the post
		// pointer — so it always copies an empty string. Native hosts cover this
		// fallback with their own crash UI; the button only ever appeared to
		// offer a recovery that does not work.
		<ErrorBoundary>
			<SlotFillProvider>
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
