export function editorLoaded() {
	if (window.editorDelegate) {
		window.editorDelegate.onEditorLoaded();
	}

	if (window.webkit) {
		window.webkit.messageHandlers.editorDelegate.postMessage({
			message: 'onEditorLoaded',
			body: {},
		});
	}
}

export function onEditorContentChanged(isEmpty = false) {
	if (window.editorDelegate) {
		window.editorDelegate.onEditorContentChanged(isEmpty);
	}

	if (window.webkit) {
		window.webkit.messageHandlers.editorDelegate.postMessage({
			message: 'onEditorContentChanged',
			body: { isEmpty },
		});
	}
}

export function onBlocksChanged(isEmpty = false) {
	if (window.editorDelegate) {
		window.editorDelegate.onBlocksChanged(isEmpty);
	}

	if (window.webkit) {
		window.webkit.messageHandlers.editorDelegate.postMessage({
			message: 'onBlocksChanged',
			body: { isEmpty },
		});
	}
}

export function showBlockPicker() {
	if (window.editorDelegate) {
		window.editorDelegate.showBlockPicker();
	}

	if (window.webkit) {
		window.webkit.messageHandlers.editorDelegate.postMessage({
			message: 'showBlockPicker',
			body: {},
		});
	}
}

export function blurEditor() {
	const activeElement = document.activeElement;

	if (activeElement && activeElement.tagName === 'P') {
		activeElement.blur();
	}
}

// FIXME: this was an attempt to fix an existing issue in Gutenberg , but it does it only
// https://a8c.slack.com/archives/D0740HYKLUX/p1719841410651649
//
// export function removeHoverEffects() {
//     for (let i = 0; i < document.styleSheets.length; i++) {
//         let styleSheet = document.styleSheets[i];
//         try {
//             if (styleSheet.cssRules) {
//                 for (let j = 0; j < styleSheet.cssRules.length; j++) {
//                     let rule = styleSheet.cssRules[j];
//                     if (rule.selectorText && rule.selectorText.includes(':hover')) {
//                         styleSheet.deleteRule(j);
//                         j--; // Adjust the index after deletion
//                     }
//                 }
//             }
//         } catch (e) {
//             console.warn('Could not access stylesheet:', styleSheet, e);
//         }
//     }
// }
