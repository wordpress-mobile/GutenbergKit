/**
 * External dependencies
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, renderHook } from '@testing-library/react';

/**
 * WordPress dependencies
 */
import { Component, useEffect } from '@wordpress/element';

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
	let events;

	beforeEach( () => {
		vi.clearAllMocks();

		events = [];
		frames = [];
		vi.stubGlobal( 'requestAnimationFrame', ( callback ) => {
			frames.push( callback );
			return frames.length;
		} );
		vi.stubGlobal( 'cancelAnimationFrame', ( id ) => {
			frames[ id - 1 ] = null;
			events.push( 'frame cancelled' );
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

	it( 'cancels the deferred frame before a crash reaches the error boundary', () => {
		// React logs the caught error, which is expected here.
		const logged = vi
			.spyOn( console, 'error' )
			.mockImplementation( () => {} );

		class Boundary extends Component {
			state = { hasError: false };

			static getDerivedStateFromError() {
				return { hasError: true };
			}

			componentDidCatch() {
				events.push( 'crash reported' );
			}

			render() {
				return this.state.hasError ? null : this.props.children;
			}
		}

		function Editor( { shouldThrow } ) {
			const [ callbackRef, , markBridgeReady ] = useEditorReady();

			useEffect( () => markBridgeReady(), [ markBridgeReady ] );

			if ( shouldThrow ) {
				throw new Error( 'Editor crashed' );
			}

			return <div ref={ callbackRef } />;
		}

		const { rerender } = render(
			<Boundary>
				<Editor shouldThrow={ false } />
			</Boundary>
		);
		revealEditor();

		rerender(
			<Boundary>
				<Editor shouldThrow />
			</Boundary>
		);
		flushFrames();

		// The boundary reports the crash to the host, so a frame left pending
		// past it would report the editor loaded afterward.
		expect( events ).toEqual( [ 'frame cancelled', 'crash reported' ] );
		expect( editorLoaded ).not.toHaveBeenCalled();

		logged.mockRestore();
	} );
} );
