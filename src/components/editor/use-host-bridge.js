/**
 * WordPress dependencies
 */
import { useEffect, useCallback, useRef } from '@wordpress/element';
import { useDispatch, useSelect } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';
import { store as editorStore } from '@wordpress/editor';
import { parse, serialize, getBlockType } from '@wordpress/blocks';
import { store as blockEditorStore } from '@wordpress/block-editor';
import { insert, create, toHTMLString } from '@wordpress/rich-text';

/**
 * Internal dependencies
 */
import { warn } from '../../utils/logger';

window.editor = window.editor || {};

export function useHostBridge( post, editorRef, markBridgeReady ) {
	const { editEntityRecord } = useDispatch( coreStore );
	const { undo, redo, switchEditorMode, savePost } =
		useDispatch( editorStore );
	const { getEditedPostAttribute, getEditedPostContent } =
		useSelect( editorStore );
	const { updateBlock, selectionChange } = useDispatch( blockEditorStore );
	const {
		getSelectedBlockClientId,
		getBlock,
		getSelectionStart,
		getSelectionEnd,
	} = useSelect( blockEditorStore );

	const editContent = useCallback(
		( edits ) => {
			editEntityRecord( 'postType', post.type, post.id, edits );
		},
		[ editEntityRecord, post.id, post.type ]
	);

	const postTitleRef = useRef( post.title.raw );
	const postContentRef = useRef( null );
	if ( postContentRef.current === null ) {
		postContentRef.current = serialize( parse( post.content.raw || '' ) );
	}

	useEffect( () => {
		window.editor.setContent = ( content ) => {
			editContent( { content: decodeURIComponent( content ) } );
		};

		window.editor.setTitle = ( title ) => {
			editContent( { title: decodeURIComponent( title ) } );
		};

		window.editor.getContent = ( completeComposition = false ) => {
			if ( completeComposition ) {
				endComposition( editorRef.current );
			}

			return getEditedPostContent();
		};

		window.editor.getTitleAndContent = ( completeComposition = false ) => {
			if ( completeComposition ) {
				endComposition( editorRef.current );
			}

			const title = getEditedPostAttribute( 'title' );
			const content = getEditedPostContent();
			const changed =
				title !== postTitleRef.current ||
				content !== postContentRef.current;

			if ( changed ) {
				postTitleRef.current = title;
				postContentRef.current = content;
			}

			return { title, content, changed };
		};

		window.editor.undo = () => {
			// Do not return the `Promise` return value to avoid host errors.
			undo();
		};

		window.editor.redo = () => {
			// Do not return the `Promise` return value to avoid host errors.
			redo();
		};

		window.editor.savePost = async () => {
			await savePost();
		};

		window.editor.switchEditorMode = ( mode ) => {
			// Do not return the `Promise` return value to avoid host errors.
			switchEditorMode( mode );
		};

		window.editor.dismissTopModal = () => {
			const target =
				editorRef.current.ownerDocument.activeElement || document.body;
			target.dispatchEvent(
				new KeyboardEvent( 'keydown', {
					key: 'Escape',
					keyCode: 27,
					which: 27,
					code: 'Escape',
					bubbles: true,
					cancelable: true,
				} )
			);
		};

		window.editor.focus = () => {
			const editable = document.querySelector(
				'[contenteditable="true"]'
			);
			if ( editable ) {
				editable.focus();
				editable.click();
			}
		};

		window.editor.appendTextAtCursor = ( text ) => {
			const selectedBlockClientId = getSelectedBlockClientId();

			if ( ! selectedBlockClientId ) {
				warn( 'Unable to append text: no block selected' );
				return false;
			}

			const block = getBlock( selectedBlockClientId );

			if ( ! block ) {
				warn(
					'Unable to append text: could not retrieve selected block'
				);
				return false;
			}

			const blockType = getBlockType( block.name );
			const hasContentAttribute = blockType?.attributes?.content;

			if ( ! hasContentAttribute ) {
				warn(
					`Unable to append text: block type ${ block.name } does not support text content`
				);
				return false;
			}

			const blockContent = block.attributes?.content || '';
			const currentValue = create( { html: blockContent } );
			const selectionStart = getSelectionStart();
			const selectionEnd = getSelectionEnd();
			const newValue = insert(
				currentValue,
				text,
				selectionStart?.offset,
				selectionEnd?.offset
			);

			updateBlock( selectedBlockClientId, {
				attributes: {
					...block.attributes,
					content: toHTMLString( { value: newValue } ),
				},
			} );

			const newCursorPosition =
				selectionStart?.offset + text.length || newValue.text.length;

			selectionChange( {
				clientId: selectionStart?.clientId || selectedBlockClientId,
				attributeKey: selectionStart?.attributeKey || 'content',
				startOffset: newCursorPosition,
				endOffset: newCursorPosition,
			} );

			return true;
		};

		// Signal that all window.editor.* methods are assigned. The native
		// host is notified only after this AND the editor element is visible
		// (coordinated by useEditorReady).
		markBridgeReady();

		return () => {
			delete window.editor.setContent;
			delete window.editor.setTitle;
			delete window.editor.getContent;
			delete window.editor.getTitleAndContent;
			delete window.editor.savePost;
			delete window.editor.undo;
			delete window.editor.redo;
			delete window.editor.switchEditorMode;
			delete window.editor.dismissTopModal;
			delete window.editor.focus;
			delete window.editor.appendTextAtCursor;
		};
	}, [
		editorRef,
		editContent,
		markBridgeReady,
		getEditedPostAttribute,
		getEditedPostContent,
		savePost,
		redo,
		switchEditorMode,
		undo,
		getSelectedBlockClientId,
		getBlock,
		getSelectionStart,
		getSelectionEnd,
		updateBlock,
		selectionChange,
	] );
}

/**
 * Ends the current text composition on the active element, if it is a
 * `contenteditable` element. This is used to ensure that the latest composition
 * text is persisted to the DOM before reading its value in the host.
 *
 * @param {Element} element The element in which to end the composition.
 *
 * @return {void}
 */
function endComposition( element ) {
	const activeElement = element?.ownerDocument.activeElement;

	if ( activeElement && activeElement.contentEditable === 'true' ) {
		const compositionEvent = new Event( 'compositionend' );
		activeElement.dispatchEvent( compositionEvent );
	}
}
