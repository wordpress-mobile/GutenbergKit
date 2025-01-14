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

export function useHostBridge(post) {
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

		window.editor.getContent = (blurInput = false) => {
			if (blurInput) {
				blurEditor();
			}

			return getEditedPostContent();
		};

		window.editor.getTitleAndContent = (blurInput = false) => {
			if (blurInput) {
				blurEditor();
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
		};
	}, [
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
 * Blurs the currently active paragraph element in the document.
 *
 * This function checks if the currently active element is a paragraph (`<p>`).
 * If it is, the function removes focus from that element.
 *
 * @todo Address the disabled eslint rule `@wordpress/no-global-active-element`.
 *
 * @return {void}
 */
function blurEditor() {
	// eslint-disable-next-line @wordpress/no-global-active-element
	const activeElement = document.activeElement;

	if (activeElement && activeElement.tagName === 'P') {
		activeElement.blur();
	}
}
