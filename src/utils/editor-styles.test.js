/**
 * External dependencies
 */
import { describe, it, expect, beforeEach, vi } from 'vitest';

/**
 * Internal dependencies
 */
import { injectEditorStyles } from './editor-styles';

// Vitest runs with `css: false`, so `?inline` imports resolve to empty strings
// and the real stylesheets never reach the module. Stub each one with an
// identifiable marker so the direction selection is observable.
vi.mock( '@wordpress/components/build-style/style.css?inline', () => ( {
	default: '.ltr-components{}',
} ) );
vi.mock( '@wordpress/block-editor/build-style/style.css?inline', () => ( {
	default: '.ltr-block-editor{}',
} ) );
vi.mock( '@wordpress/block-library/build-style/editor.css?inline', () => ( {
	default: '.ltr-block-library{}',
} ) );
vi.mock( '@wordpress/format-library/build-style/style.css?inline', () => ( {
	default: '.ltr-format-library{}',
} ) );
vi.mock( '@wordpress/editor/build-style/style.css?inline', () => ( {
	default: '.ltr-editor{}',
} ) );

vi.mock( '@wordpress/components/build-style/style-rtl.css?inline', () => ( {
	default: '.rtl-components{}',
} ) );
vi.mock( '@wordpress/block-editor/build-style/style-rtl.css?inline', () => ( {
	default: '.rtl-block-editor{}',
} ) );
vi.mock( '@wordpress/block-library/build-style/editor-rtl.css?inline', () => ( {
	default: '.rtl-block-library{}',
} ) );
vi.mock( '@wordpress/format-library/build-style/style-rtl.css?inline', () => ( {
	default: '.rtl-format-library{}',
} ) );
vi.mock( '@wordpress/editor/build-style/style-rtl.css?inline', () => ( {
	default: '.rtl-editor{}',
} ) );

const STYLE_ELEMENT_ID = 'gutenberg-kit-editor-styles';

const getStyleElement = () => document.getElementById( STYLE_ELEMENT_ID );

describe( 'injectEditorStyles', () => {
	beforeEach( () => {
		getStyleElement()?.remove();
	} );

	it( 'injects a single style element into the document head', () => {
		injectEditorStyles( false );

		const element = getStyleElement();
		expect( element ).not.toBeNull();
		expect( element.tagName ).toBe( 'STYLE' );
		expect( element.parentElement ).toBe( document.head );
	} );

	it( 'injects the left-to-right stylesheets in cascade order', () => {
		injectEditorStyles( false );

		expect( getStyleElement().textContent ).toBe(
			[
				'.ltr-components{}',
				'.ltr-block-editor{}',
				'.ltr-block-library{}',
				'.ltr-format-library{}',
				'.ltr-editor{}',
			].join( '\n' )
		);
	} );

	it( 'injects the right-to-left stylesheets in cascade order', () => {
		injectEditorStyles( true );

		expect( getStyleElement().textContent ).toBe(
			[
				'.rtl-components{}',
				'.rtl-block-editor{}',
				'.rtl-block-library{}',
				'.rtl-format-library{}',
				'.rtl-editor{}',
			].join( '\n' )
		);
	} );

	// The `-rtl` bundles are full rewrites rather than overrides, so injecting
	// both would let source order decide which direction every user gets.
	it( 'injects only one direction at a time', () => {
		injectEditorStyles( true );

		const content = getStyleElement().textContent;
		expect( content ).toContain( '.rtl-components{}' );
		expect( content ).not.toContain( '.ltr-components{}' );
	} );

	it( 'replaces the previous styles rather than accumulating them', () => {
		injectEditorStyles( false );
		injectEditorStyles( true );

		expect(
			document.querySelectorAll( `#${ STYLE_ELEMENT_ID }` )
		).toHaveLength( 1 );
	} );
} );
