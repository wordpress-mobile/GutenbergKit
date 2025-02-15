/**
 * WordPress dependencies
 */
import { PostTitleRaw, PostTextEditor } from '@wordpress/editor';

/**
 * Internal dependencies
 */
import './style.scss';

/**
 * TextEditor component renders a text editor with an optional title.
 *
 * @param {Object}  props           Component props.
 * @param {boolean} props.hideTitle Whether to hide the title input.
 *
 * @return {JSX.Element} The rendered text editor component.
 */
export default function TextEditor( { hideTitle } ) {
	return (
		<div className="gutenberg-kit-text-editor">
			{ ! hideTitle && <PostTitleRaw /> }
			<PostTextEditor />
		</div>
	);
}
