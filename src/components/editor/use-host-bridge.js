/**
 * WordPress dependencies
 */
import { useEffect, useCallback, useRef } from '@wordpress/element';
import { useDispatch, useSelect } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';
import { store as editorStore } from '@wordpress/editor';
import { store as noticesStore } from '@wordpress/notices';
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
	const { removeNotice } = useDispatch( noticesStore );
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

	const postTitleRef = useRef( normalizeAttribute( post.title ) );
	const postContentRef = useRef( null );
	if ( postContentRef.current === null ) {
		postContentRef.current = serialize(
			parse( normalizeAttribute( post.content ) )
		);
	}

	useEffect( () => {
		window.editor.setContent = ( content ) => {
			editContent( { content: decodeURIComponent( content ) } );
		};

		window.editor.setTitle = ( title ) => {
			editContent( { title: decodeURIComponent( title ) } );
		};

		// Convenience accessor for contexts where only the content is needed
		// (e.g. a comment editor with no title field). Delegates to
		// getTitleAndContent so normalization happens in one place.
		window.editor.getContent = ( completeComposition = false ) => {
			const { content } =
				window.editor.getTitleAndContent( completeComposition );
			return content;
		};

		window.editor.getTitleAndContent = ( completeComposition = false ) => {
			if ( completeComposition ) {
				endComposition( editorRef.current );
			}

			const title = normalizeAttribute(
				getEditedPostAttribute( 'title' )
			);
			const content = normalizeAttribute( getEditedPostContent() );
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
			try {
				// Await the lifecycle so hosts can sequence persistence after
				// plugin side-effects settle, do not return the `Promise` return value
				// to avoid host errors.
				await savePost();
			} finally {
				// Native hosts display their own save feedback, disable the default
				removeNotice( 'editor-save' );
			}
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
		removeNotice,
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
 * Normalizes a WordPress data store attribute to a plain string.
 *
 * The data store may return either a plain string or a `{ raw, rendered }`
 * object depending on internal state (e.g. before vs. after the user edits
 * a field). This function always extracts the raw string so the host app
 * receives a consistent type.
 *
 * @param {string|Object|null|undefined} value The value from a data store selector.
 * @return {string} The raw string value.
 */
function normalizeAttribute( value ) {
	if ( value === null || value === undefined || Array.isArray( value ) ) {
		return '';
	}
	if ( typeof value === 'object' ) {
		return value.raw ?? '';
	}
	return String( value );
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
