/**
 * WordPress dependencies
 */
import { PostTitleRaw, PostTextEditor } from '@wordpress/editor';

/**
 * Internal dependencies
 */
import './style.scss';

export default function TextEditor() {
	return (
		<div className="gutenberg-kit-text-editor">
			<PostTitleRaw />
			<PostTextEditor />
		</div>
	);
}
