/**
 * WordPress dependencies
 */
import { forwardRef } from '@wordpress/element';
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
 * @param {Object}  ref             Forwarded ref.
 *
 * @return {Element} The rendered text editor component.
 */
const TextEditor = forwardRef( function TextEditor( { hideTitle }, ref ) {
	return (
		<div className="gutenberg-kit-text-editor" ref={ ref }>
			{ ! hideTitle && <PostTitleRaw /> }
			<PostTextEditor />
		</div>
	);
} );

export default TextEditor;
