/**
 * Platform detection for GutenbergKit.
 *
 * Detects whether the editor is running on iOS, Android, or in a web browser
 * (dev mode) based on native bridge globals set up by the native platforms.
 */

const currentPlatform = detectPlatform();

/**
 * Platform operating system types.
 *
 * @typedef {'ios' | 'android' | 'web'} PlatformOS
 */

/**
 * Platform information object.
 *
 * @type {Object}
 * @property {PlatformOS} OS        - The current platform operating system
 * @property {boolean}    isIOS     - Whether running on iOS
 * @property {boolean}    isAndroid - Whether running on Android
 * @property {boolean}    isWeb     - Whether running in web browser/dev mode
 * @property {boolean}    isNative  - Whether running on a native platform (iOS or Android)
 */
export const Platform = {
	OS: currentPlatform,
	isIOS: currentPlatform === 'ios',
	isAndroid: currentPlatform === 'android',
	isWeb: currentPlatform === 'web',
	isNative: currentPlatform === 'ios' || currentPlatform === 'android',
};

/**
 * Detects the current platform based on native bridge globals.
 *
 * - iOS sets up `window.webkit.messageHandlers.editorDelegate`
 * - Android sets up `window.editorDelegate`
 * - Neither exists in browser/dev mode
 *
 * @return {PlatformOS} The detected platform
 */
function detectPlatform() {
	if ( typeof window === 'undefined' ) {
		return 'web';
	}

	// iOS uses WebKit message handlers
	if ( window.webkit?.messageHandlers?.editorDelegate ) {
		return 'ios';
	}

	// Android uses JavaScript interface
	if ( window.editorDelegate ) {
		return 'android';
	}

	// Running in browser/dev mode
	return 'web';
}
