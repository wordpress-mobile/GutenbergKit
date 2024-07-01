export function postMessage(message, parameters = {}) {
    if (window.webkit) {
        const value = { message: message, body: parameters }
        window.webkit.messageHandlers.editorDelegate.postMessage(value);
    };
};

export function removeHoverEffects() {
    for (let i = 0; i < document.styleSheets.length; i++) {
        let styleSheet = document.styleSheets[i];
        try {
            if (styleSheet.cssRules) {
                for (let j = 0; j < styleSheet.cssRules.length; j++) {
                    let rule = styleSheet.cssRules[j];
                    if (rule.selectorText && rule.selectorText.includes(':hover')) {
                        styleSheet.deleteRule(j);
                        j--; // Adjust the index after deletion
                    }
                }
            }
        } catch (e) {
            console.warn('Could not access stylesheet:', styleSheet, e);
        }
    }
}