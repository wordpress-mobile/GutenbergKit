/**
 * WordPress dependencies
 */
import { useState, useEffect } from '@wordpress/element';

/**
 * Tracks whether the virtual keyboard is visible based on focus and blur
 * events. This not entirely reliable, but is a good approximation for now until
 * the VirtualKeyboard API is more widely supported.
 *
 * @return {boolean} Whether the keyboard is visible.
 */
export function useKeyboardVisibility() {
	const [isKeyboardVisible, setIsKeyboardVisible] = useState(false);

	useEffect(() => {
		let handleFocusTimeout, handleBlurTimeout;

		const handleFocus = (e) => {
			if (isEditableControl(e.target)) {
				// Timeout used to mirror blur timeout
				handleFocusTimeout = setTimeout(() => {
					setIsKeyboardVisible(true);
				}, 0);
			}
		};
		const handleBlur = () => {
			// Timeout required to ensure click event is processed before blur handler
			handleBlurTimeout = setTimeout(() => {
				setIsKeyboardVisible(false);
			}, 0);
		};

		document.addEventListener('focus', handleFocus, true);
		document.addEventListener('blur', handleBlur, true);

		return () => {
			document.removeEventListener('focus', handleFocus, true);
			document.removeEventListener('blur', handleBlur, true);
			clearTimeout(handleFocusTimeout);
			clearTimeout(handleBlurTimeout);
		};
	}, []);

	return [isKeyboardVisible, setIsKeyboardVisible];
}

/**
 * Checks if the given element is an editable control.
 *
 * An editable control is defined as an input element, a textarea element,
 * or any element with the `contenteditable` attribute set to true. This is not
 * an exhaustive list of all editable elements or states, but it is a good
 * representation
 *
 * @param {HTMLElement} element - The element to check.
 *
 * @return {boolean} True if the element is an editable control, false otherwise.
 */
function isEditableControl(element) {
	if (!element) {
		return false;
	}

	const active = element.ownerDocument.activeElement;
	return (
		active.tagName === 'INPUT' ||
		active.tagName === 'TEXTAREA' ||
		active.isContentEditable
	);
}
