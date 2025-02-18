/**
 * WordPress dependencies
 */
import { EditorSnackbars, ErrorBoundary } from '@wordpress/editor';

/**
 * Internal dependencies
 */
import Editor from '../editor';
import EditorLoadNotice from '../editor-load-notice';
import './style.scss';

/**
 * Top-level layout, including the Editor component wrapped in an ErrorBoundary.
 *
 * @param {Object} props The settings passed along to the Editor component.
 *
 * @return {JSX.Element} The rendered Layout component.
 */
export default function Layout( props ) {
	return (
		<ErrorBoundary canCopyContent>
			<Editor { ...props }>
				<EditorSnackbars />
			</Editor>
			<EditorLoadNotice className="gutenberg-kit-layout__load-notice" />
		</ErrorBoundary>
	);
}
