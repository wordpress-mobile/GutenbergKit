export function getGBKit() {
	if (window.GBKit) {
		return window.GBKit;
	}

	const emptyObject = {};
	try {
		return JSON.parse(localStorage.getItem('GBKit')) || emptyObject;
	} catch (error) {
		console.error('Failed parsing GBKit from localStorage:', error);
		return emptyObject;
	}
}

export function postMessage(message, parameters = {}) {
	if (window.webkit) {
		const value = { message: message, body: parameters };
		window.webkit.messageHandlers.editorDelegate.postMessage(value);
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
