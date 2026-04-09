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
import { addFilter, removeFilter } from '@wordpress/hooks';
import apiFetch from '@wordpress/api-fetch';

/**
 * Internal dependencies
 */
import { warn } from '../../utils/logger';
import { hydratePost } from '../../utils/bridge';

window.editor = window.editor || {};

export function useHostBridge( post, editorRef, markBridgeReady ) {
	const { editEntityRecord } = useDispatch( coreStore );
	const { getEditedEntityRecord, getLastEntitySaveError } =
		useSelect( coreStore );
	const { undo, redo, switchEditorMode, savePost } =
		useDispatch( editorStore );
	const { removeNotice } = useDispatch( noticesStore );
	const {
		getEditedPostAttribute,
		getEditedPostContent,
		didPostSaveRequestFail,
		getCurrentPostId,
	} = useSelect( editorStore );
	const { updateBlock, selectionChange } = useDispatch( blockEditorStore );
	const {
		getSelectedBlockClientId,
		getBlock,
		getSelectionStart,
		getSelectionEnd,
	} = useSelect( blockEditorStore );

	const editContent = useCallback(
		( edits ) => {
			editEntityRecord(
				'postType',
				post.type,
				getCurrentPostId(),
				edits
			);
		},
		[ editEntityRecord, getCurrentPostId, post.type ]
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

			const blockContent = normalizeAttribute(
				block.attributes?.content
			);
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

		window.editor.savePost = async () => {
			const isNewPost = getCurrentPostId() <= 0;
			let createdId = null;

			const saveOptions = {};
			if ( isNewPost ) {
				saveOptions.__unstableFetch = async ( fetchOptions ) => {
					const result = await apiFetch( fetchOptions );
					if ( fetchOptions.method === 'POST' && result?.id > 0 ) {
						createdId = result.id;
					}
					return result;
				};
			}

			try {
				await savePost( saveOptions );
			} finally {
				// Suppress the editor's built-in save notice — the native
				// host shows its own platform-appropriate feedback.
				removeNotice( 'editor-save' );
			}

			// Gutenberg's savePost() never throws — it stores errors
			// internally via REQUEST_POST_UPDATE_FAILURE. Surface the
			// failure so the native host can display an error.
			if ( didPostSaveRequestFail() ) {
				const postId = getCurrentPostId();
				const saveError = getLastEntitySaveError(
					'postType',
					post.type,
					postId
				);
				throw new Error(
					saveError?.message || saveError || 'Post save failed'
				);
			}

			// After a successful create, record the server-assigned ID as
			// an edit so subsequent saves use PUT /{restBase}/{id} instead
			// of POST.  We deliberately avoid setEditedPost() — switching
			// entity records mid-session causes the title's contentEditable
			// to lose its value.
			if ( isNewPost && createdId ) {
				editEntityRecord( 'postType', post.type, getCurrentPostId(), {
					id: createdId,
				} );
			}

			// Return the saved entity so the native host can use it in
			// post-save delegate callbacks.  getEditedEntityRecord
			// returns raw-extracted strings for title/content, but the
			// native EditorPost parser expects { raw, rendered } objects.
			const postId = getCurrentPostId();
			const savedRecord = getEditedEntityRecord(
				'postType',
				post.type,
				postId
			);
			return {
				...savedRecord,
				title:
					typeof savedRecord.title === 'string'
						? { raw: savedRecord.title }
						: savedRecord.title,
				content: { raw: getEditedPostContent() },
			};
		};

		// Register a pre-save filter so that every save path (native bridge,
		// keyboard shortcut, plugin-triggered, autosave) hydrates the post
		// with native-side metadata before the PUT is sent.
		addFilter(
			'editor.preSavePost',
			'GutenbergKit/hydratePost',
			async ( edits ) => {
				const postId = getCurrentPostId();
				const currentPost = getEditedEntityRecord(
					'postType',
					post.type,
					postId
				);
				const modifiedPost = await hydratePost( currentPost );
				if ( modifiedPost ) {
					// Strip `meta` — the native host round-trips it
					// from the entity record but the REST API may
					// reject values whose types changed during the
					// Foundation↔JSON conversion (e.g. integer meta
					// fields returned as doubles).
					const { meta: _meta, ...safeFields } = modifiedPost;
					edits = { ...edits, ...safeFields };
				}

				// For new posts (id <= 0), strip the id so Gutenberg sends
				// POST (create) instead of PUT to /{restBase}/{id}.
				if ( edits.id !== undefined && edits.id <= 0 ) {
					const { id: _id, ...rest } = edits;
					return rest;
				}

				return edits;
			}
		);

		// Signal that all window.editor.* methods are assigned. The native
		// host is notified only after this AND the editor element is visible
		// (coordinated by useEditorReady).
		markBridgeReady();

		return () => {
			delete window.editor.setContent;
			delete window.editor.setTitle;
			delete window.editor.getContent;
			delete window.editor.getTitleAndContent;
			delete window.editor.undo;
			delete window.editor.redo;
			delete window.editor.switchEditorMode;
			delete window.editor.dismissTopModal;
			delete window.editor.focus;
			delete window.editor.appendTextAtCursor;
			delete window.editor.savePost;
			removeFilter( 'editor.preSavePost', 'GutenbergKit/hydratePost' );
		};
	}, [
		editorRef,
		editContent,
		getEditedEntityRecord,
		getLastEntitySaveError,
		markBridgeReady,
		getEditedPostAttribute,
		getEditedPostContent,
		getCurrentPostId,
		post.type,
		redo,
		savePost,
		didPostSaveRequestFail,
		removeNotice,
		switchEditorMode,
		undo,
		editEntityRecord,
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
