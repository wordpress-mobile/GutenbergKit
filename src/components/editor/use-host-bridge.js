/**
 * WordPress dependencies
 */
import { useEffect, useCallback, useRef } from '@wordpress/element';
import { useDispatch, useSelect, dispatch, select } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';
import { store as editorStore } from '@wordpress/editor';
import { store as blockEditorStore } from '@wordpress/block-editor';
import { parse, serialize, createBlock } from '@wordpress/blocks';

/**
 * Internal dependencies
 */

window.editor = window.editor || {};
window.editor._savedInsertionPoint = null;

export function useHostBridge( post, editorRef ) {
	const { editEntityRecord } = useDispatch( coreStore );
	const { undo, redo, switchEditorMode } = useDispatch( editorStore );
	const { getEditedPostAttribute, getEditedPostContent } =
		useSelect( editorStore );

	// Track the current selection and insertion point
	const { selectedBlockClientId, blockInsertionPoint } = useSelect(
		( selectFn ) => {
			const { getSelectedBlockClientId, getBlockInsertionPoint } =
				selectFn( blockEditorStore );
			return {
				selectedBlockClientId: getSelectedBlockClientId(),
				blockInsertionPoint: getBlockInsertionPoint(),
			};
		},
		[]
	);

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

	// Continuously update the saved insertion point whenever selection changes
	useEffect( () => {
		// Only update if we have a selected block OR if we're clearing selection but already have a saved point
		if ( selectedBlockClientId !== null ) {
			// We have a selected block, save its position
			window.editor._savedInsertionPoint = {
				rootClientId: blockInsertionPoint?.rootClientId,
				index: blockInsertionPoint?.index || 0,
				selectedBlockClientId,
			};
		} else if (
			! window.editor._savedInsertionPoint ||
			! window.editor._savedInsertionPoint.selectedBlockClientId
		) {
			// Only update to null selection if we don't have a previously selected block
			// This prevents overwriting a good insertion point when focus is lost
			if ( blockInsertionPoint && blockInsertionPoint.index !== null ) {
				window.editor._savedInsertionPoint = {
					rootClientId: blockInsertionPoint?.rootClientId,
					index: blockInsertionPoint?.index || 0,
					selectedBlockClientId: null,
				};
			}
		}
		// If selectedBlockClientId is null but we had a previous selection, keep the old insertion point
	}, [ selectedBlockClientId, blockInsertionPoint ] );

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

		window.editor.switchEditorMode = ( mode ) => {
			// Do not return the `Promise` return value to avoid host errors.
			switchEditorMode( mode );
		};

		window.editor.insertBlock = ( blockName ) => {
			try {
				const block = createBlock( blockName );

				// Check if we have a saved insertion point
				if ( window.editor._savedInsertionPoint ) {
					const { 
						selectedBlockClientId: savedSelectedBlockClientId, 
						index, 
						rootClientId 
					} = window.editor._savedInsertionPoint;

					// Try to use insertBlocks (plural) which might handle positioning better
					const { insertBlocks } = dispatch( blockEditorStore );

					if ( savedSelectedBlockClientId ) {
						// We have a selected block, insert after it
						// First, try to get the block directly
						const selectedBlock = select(
							blockEditorStore
						).getBlock( savedSelectedBlockClientId );
						if ( selectedBlock ) {
							const parentClientId = select(
								blockEditorStore
							).getBlockRootClientId( savedSelectedBlockClientId );
							const blockIndex = select(
								blockEditorStore
							).getBlockIndex( savedSelectedBlockClientId );

							// Use insertBlocks with explicit position
							insertBlocks(
								[ block ],
								blockIndex + 1,
								parentClientId
							);
						} else {
							insertBlocks( [ block ], index, rootClientId );
						}
					} else {
						// No selected block, use the saved index
						insertBlocks( [ block ], index, rootClientId );
					}
				} else {
					// No saved insertion point
					dispatch( blockEditorStore ).insertBlock( block );
				}

				// Select the newly inserted block to help with focusing
				setTimeout( () => {
					dispatch( blockEditorStore ).selectBlock( block.clientId );
				}, 100 );
			} catch ( error ) {
				// eslint-disable-next-line no-console
				console.error( 'Error in insertBlock:', error );
			}
		};

		window.editor.insertMediaFromFiles = ( mediaItems ) => {
			// Do not return the Promise to avoid host errors
			import( '../../utils/bridge' ).then( ( { insertMediaFromFiles } ) => {
				insertMediaFromFiles( mediaItems );
			} );
		};

		return () => {
			delete window.editor.setContent;
			delete window.editor.setTitle;
			delete window.editor.getContent;
			delete window.editor.getTitleAndContent;
			delete window.editor.undo;
			delete window.editor.redo;
			delete window.editor.switchEditorMode;
			delete window.editor.insertBlock;
			delete window.editor.insertMediaFromFiles;
			window.editor._savedInsertionPoint = null;
		};
	}, [
		editorRef,
		editContent,
		getEditedPostAttribute,
		getEditedPostContent,
		redo,
		switchEditorMode,
		undo,
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
