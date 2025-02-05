/**
 * WordPress dependencies
 */
import { useEffect, useCallback, useRef } from '@wordpress/element';
import { useDispatch, useSelect, subscribe } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';
import { store as editorStore } from '@wordpress/editor';

/**
 * Internal dependencies
 */
import { onEditorContentChanged } from '../../utils/bridge';

window.editor = window.editor || {};

export function useHostBridge(post, editorRef) {
	const { editEntityRecord } = useDispatch(coreStore);
	const { undo, redo, switchEditorMode } = useDispatch(editorStore);
	const { getEditedPostAttribute, getEditedPostContent } =
		useSelect(editorStore);

	const editContent = useCallback(
		(edits) => {
			editEntityRecord('postType', post.type, post.id, edits);
		},
		[editEntityRecord, post.id, post.type]
	);

	useEffect(() => {
		window.editor.setContent = (content) => {
			editContent({ content: decodeURIComponent(content) });
		};

		window.editor.setTitle = (title) => {
			editContent({ title: decodeURIComponent(title) });
		};

		window.editor.getContent = (completeComposition = false) => {
			if (completeComposition) {
				endComposition(editorRef.current);
			}

			return getEditedPostContent();
		};

		window.editor.getTitleAndContent = (completeComposition = false) => {
			if (completeComposition) {
				endComposition(editorRef.current);
			}

			return {
				title: getEditedPostAttribute('title'),
				content: getEditedPostContent(),
			};
		};

		window.editor.undo = () => {
			// Do not return the `Promise` return value to avoid host errors.
			undo();
		};

		window.editor.redo = () => {
			// Do not return the `Promise` return value to avoid host errors.
			redo();
		};

		window.editor.switchEditorMode = (mode) => {
			// Do not return the `Promise` return value to avoid host errors.
			switchEditorMode(mode);
		};

		return () => {
			delete window.editor.setContent;
			delete window.editor.setTitle;
			delete window.editor.getContent;
			delete window.editor.getTitleAndContent;
			delete window.editor.undo;
			delete window.editor.redo;
			delete window.editor.switchEditorMode;
		};
	}, [
		editorRef,
		editContent,
		getEditedPostAttribute,
		getEditedPostContent,
		redo,
		switchEditorMode,
		undo,
	]);

	const postTitleRef = useRef(post.title);
	const postContentRef = useRef(post.content);

	useEffect(() => {
		return subscribe(() => {
			const { title, content } = window.editor.getTitleAndContent();
			if (
				title !== postTitleRef.current ||
				content !== postContentRef.current
			) {
				onEditorContentChanged();
				postTitleRef.current = title;
				postContentRef.current = content;
			}
		});
	}, []);
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
function endComposition(element) {
	const activeElement = element?.ownerDocument.activeElement;

	if (activeElement && activeElement.contentEditable === 'true') {
		const compositionEvent = new Event('compositionend');
		activeElement.dispatchEvent(compositionEvent);
	}
}
