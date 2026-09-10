/**
 * External dependencies
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook } from '@testing-library/react';

/**
 * Internal dependencies
 */
import { useEditorReady } from '../use-editor-ready';
import { editorLoaded } from '../../../utils/bridge';

vi.mock( '../../../utils/bridge', () => ( {
	editorLoaded: vi.fn(),
} ) );

describe( 'useEditorReady', () => {
	let frames;
	let revealEditor;

	beforeEach( () => {
		vi.clearAllMocks();

		frames = [];
		vi.stubGlobal( 'requestAnimationFrame', ( callback ) => {
			frames.push( callback );
			return frames.length;
		} );
		vi.stubGlobal( 'cancelAnimationFrame', ( id ) => {
			frames[ id - 1 ] = null;
		} );

		vi.stubGlobal(
			'IntersectionObserver',
			class {
				constructor( callback ) {
					revealEditor = () =>
						callback( [ { isIntersecting: true } ] );
				}
				observe() {}
				disconnect() {}
			}
		);
	} );

	afterEach( () => {
		vi.unstubAllGlobals();
	} );

	function renderReadyEditor() {
		const hook = renderHook( () => useEditorReady() );
		const [ callbackRef, , markBridgeReady ] = hook.result.current;

		callbackRef( document.createElement( 'div' ) );
		revealEditor();
		markBridgeReady();

		return hook;
	}

	function flushFrames() {
		frames.splice( 0 ).forEach( ( callback ) => callback?.() );
	}

	it( 'notifies the host once the bridge is ready and the editor is visible', () => {
		renderReadyEditor();
		flushFrames();

		expect( editorLoaded ).toHaveBeenCalledTimes( 1 );
	} );

	it( 'does not notify the host when the editor unmounts before the deferred frame', () => {
		const { unmount } = renderReadyEditor();

		unmount();
		flushFrames();

		expect( editorLoaded ).not.toHaveBeenCalled();
	} );
} );
