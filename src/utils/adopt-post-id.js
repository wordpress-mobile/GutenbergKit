import { dispatch, select } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';
import { store as editorStore } from '@wordpress/editor';
import { store as blockEditorStore } from '@wordpress/block-editor';

/**
 * Switches the editor to the ID the server gave the post it's editing, keeping
 * its unsaved edits.
 *
 * Gutenberg stores the post under its ID, so the record moves to the new ID
 * with its edits, and the editor follows it. The undo history isn't moved.
 *
 * @param {number} newId The post's ID on the server.
 * @return {void}
 */
export function adoptPostId( newId ) {
	const type = select( editorStore ).getCurrentPostType();
	const id = select( editorStore ).getCurrentPostId();
	if ( ! type || newId === id ) {
		return;
	}

	const { getEntityRecord, getEntityRecordEdits } = select( coreStore );
	const { receiveEntityRecords, finishResolution, editEntityRecord } =
		dispatch( coreStore );
	const edits = getEntityRecordEdits( 'postType', type, id ) ?? {};

	receiveEntityRecords( 'postType', type, {
		...getEntityRecord( 'postType', type, id ),
		id: newId,
	} );
	finishResolution( 'getEntityRecord', [ 'postType', type, newId ] );
	// GBK's request middlewares read the post's ID from here.
	if ( window.GBKit ) {
		window.GBKit.post = { ...window.GBKit.post, id: newId };
	}
	// Without a `blocks` edit, every block remounts and the next keystrokes are
	// lost.
	editEntityRecord(
		'postType',
		type,
		newId,
		{
			...edits,
			blocks: edits.blocks ?? select( blockEditorStore ).getBlocks(),
		},
		{ undoIgnore: true }
	);
	dispatch( editorStore ).setEditedPost( type, newId );
}
