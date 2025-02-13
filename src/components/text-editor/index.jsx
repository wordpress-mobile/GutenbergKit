/**
 * WordPress dependencies
 */
import { PostTitleRaw, PostTextEditor } from '@wordpress/editor';

/**
 * Internal dependencies
 */
import './style.scss';

export default function TextEditor({ hideTitle }) {
	return (
		<div className="gutenberg-kit-text-editor">
			{!hideTitle && <PostTitleRaw />}
			<PostTextEditor />
		</div>
	);
}
