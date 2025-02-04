/**
 * WordPress dependencies
 */
import { EditorSnackbars, ErrorBoundary } from '@wordpress/editor';
import { Popover } from '@wordpress/components';

/**
 * Internal dependencies
 */
import Editor from './editor';

/**
 * Top-level layout, including the Editor component wrapped in an ErrorBoundary.
 *
 * @param {Object} props The settings passed along to the Editor component.
 *
 * @return {JSX.Element} The rendered Layout component.
 */
export default function Layout(props) {
	return (
		<ErrorBoundary>
			<Editor {...props}>
				<EditorSnackbars />
			</Editor>
			<Popover.Slot />
		</ErrorBoundary>
	);
}
