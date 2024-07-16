export function editorLoaded() {
	console.log("Firing JS editorLoaded event");

	if(editorDelegate) {
		editorDelegate.onEditorLoaded();
	}

	if(window.webkit) {
		window.webkit.messageHandlers.editorDelegate.postMessage({
			message: 'editorLoaded',
			body: {}
		});
	}
}

export function onBlocksChanged(isEmpty = false) {
	if(editorDelegate) {
		editorDelegate.onBlocksChanged(isEmpty);
	}

	if(window.webkit) {
		window.webkit.messageHandlers.editorDelegate.postMessage({
			message: 'onBlocksChanged',
			body: { isEmpty: isEmpty }
		});
	}
}

export function showBlockPicker() {
	if(editorDelegate) {
		editorDelegate.showBlockPicker();
	}

	if(window.webkit) {
		window.webkit.messageHandlers.editorDelegate.postMessage({
			message: 'showBlockPicker',
			body: {}
		});
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
