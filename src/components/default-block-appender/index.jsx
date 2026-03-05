/**
 * WordPress dependencies
 */
import { createBlock } from '@wordpress/blocks';
import { useDispatch, useSelect } from '@wordpress/data';
import { __ } from '@wordpress/i18n';
import { store as blockEditorStore } from '@wordpress/block-editor';

/**
 * Internal dependencies
 */
import './style.scss';

/**
 * Renders a hidden button that, when clicked, inserts a new paragraph block
 * at the end of the block editor.
 *
 * @return {Element} The rendered button element.
 */
export default function DefaultBlockAppender() {
	const { insertBlock } = useDispatch( blockEditorStore );
	const { blockCount } = useSelect( ( select ) => {
		const { getBlockCount } = select( blockEditorStore );
		return {
			blockCount: getBlockCount(),
		};
	} );

	const onAddParagraphBlock = () => {
		const paragraphBlock = createBlock( 'core/paragraph' );
		insertBlock( paragraphBlock, blockCount );
	};

	return (
		<button
			aria-label={ __( 'Add paragraph block', 'gutenberg-kit' ) }
			onClick={ onAddParagraphBlock }
			className="gutenberg-kit-default-block-appender"
		></button>
	);
}
