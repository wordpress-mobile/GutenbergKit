export function postMessage(message, parameters = {}) {
    if (window.webkit) {
        const value = { message: message, body: parameters }
        window.webkit.messageHandlers.editorDelegate.postMessage(value);
    };
};