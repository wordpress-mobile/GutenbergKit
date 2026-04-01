/**
 * WordPress dependencies
 */
import { useRef, useCallback } from '@wordpress/element';

/**
 * Internal dependencies
 */
import { editorLoaded } from '../../utils/bridge';

/**
 * Coordinates two readiness conditions before signaling the native host:
 * 1. The host bridge methods (window.editor.*) have been assigned
 * 2. The editor element is visible in the viewport
 *
 * @return {Array} A [callbackRef, editorRef, markBridgeReady] tuple.
 *   - callbackRef: Attach to the editor root element's `ref` prop.
 *   - editorRef: Standard ref for imperative access to the DOM node.
 *   - markBridgeReady: Callback for useHostBridge to signal bridge readiness.
 */
export function useEditorReady() {
	const editorRef = useRef( null );
	const bridgeReady = useRef( false );
	const editorVisible = useRef( false );
	const notified = useRef( false );
	const observerRef = useRef( null );

	const tryNotify = useCallback( () => {
		if (
			bridgeReady.current &&
			editorVisible.current &&
			! notified.current
		) {
			notified.current = true;
			// Defer one frame so the browser has painted the editor content
			// before the native host starts the fade-in animation.
			requestAnimationFrame( editorLoaded );
		}
	}, [] );

	const markBridgeReady = useCallback( () => {
		bridgeReady.current = true;
		tryNotify();
	}, [ tryNotify ] );

	const callbackRef = useCallback(
		( node ) => {
			if ( observerRef.current ) {
				observerRef.current.disconnect();
				observerRef.current = null;
			}

			editorRef.current = node;

			if ( ! node ) {
				return;
			}

			const observer = new IntersectionObserver( ( entries ) => {
				entries.forEach( ( entry ) => {
					if ( entry.isIntersecting ) {
						editorVisible.current = true;
						tryNotify();
						observer.disconnect();
					}
				} );
			} );

			observer.observe( node );
			observerRef.current = observer;
		},
		[ tryNotify ]
	);

	return [ callbackRef, editorRef, markBridgeReady ];
}
