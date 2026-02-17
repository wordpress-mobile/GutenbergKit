/**
 * External dependencies
 */
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import EditorPage from './editor-page';

/**
 * Type text into a new paragraph block and split it at the given position.
 *
 * @param {EditorPage}                      editor        EditorPage instance.
 * @param {import('@playwright/test').Page} page          Playwright page object.
 * @param {string}                          text          Text to type.
 * @param {number}                          splitPosition Character offset where Enter is pressed.
 */
async function typeAndSplit( editor, page, text, splitPosition ) {
	await editor.clickBlockAppender();
	await page.keyboard.type( text );
	await editor.moveCaretTo( splitPosition );
	await page.keyboard.press( 'Enter' );
}

test.describe( 'Split and Merge Blocks', () => {
	test( 'should split a paragraph block with Enter', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await typeAndSplit( editor, page, 'FirstSecond', 5 );

		const blocks = await editor.getBlocks();
		expect( blocks ).toHaveLength( 2 );
		expect( blocks[ 0 ].attributes.content ).toBe( 'First' );
		expect( blocks[ 1 ].attributes.content ).toBe( 'Second' );
	} );

	test( 'should merge two paragraph blocks with Backspace', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		// Create two blocks by typing and splitting.
		await typeAndSplit( editor, page, 'FirstSecond', 5 );

		// Cursor is now at the start of the second block. Press Backspace to merge.
		await page.keyboard.press( 'Home' );
		await page.keyboard.press( 'Backspace' );

		const blocks = await editor.getBlocks();
		expect( blocks ).toHaveLength( 1 );
		expect( blocks[ 0 ].attributes.content ).toBe( 'FirstSecond' );
	} );

	test( 'should preserve content after split and merge roundtrip', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		const originalText = 'The quick brown fox';

		// Split after "The quick" (position 9).
		await typeAndSplit( editor, page, originalText, 9 );

		let blocks = await editor.getBlocks();
		expect( blocks ).toHaveLength( 2 );

		// Merge back.
		await page.keyboard.press( 'Home' );
		await page.keyboard.press( 'Backspace' );

		blocks = await editor.getBlocks();
		expect( blocks ).toHaveLength( 1 );
		expect( blocks[ 0 ].attributes.content ).toBe( originalText );
	} );

	test( 'should split and merge preserving inline formatting', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.clickBlockAppender();

		// Type "Hello " then bold "World".
		await page.keyboard.type( 'Hello ' );
		await editor.clickBold();
		await page.keyboard.type( 'World' );
		await editor.clickBold();

		// Split between "Hello " and "World".
		await editor.moveCaretTo( 6 );
		await page.keyboard.press( 'Enter' );

		let blocks = await editor.getBlocks();
		expect( blocks ).toHaveLength( 2 );
		expect( blocks[ 0 ].attributes.content ).toBe( 'Hello ' );
		expect( blocks[ 1 ].attributes.content ).toBe(
			'<strong>World</strong>'
		);

		// Merge back.
		await page.keyboard.press( 'Home' );
		await page.keyboard.press( 'Backspace' );

		blocks = await editor.getBlocks();
		expect( blocks ).toHaveLength( 1 );
		expect( blocks[ 0 ].attributes.content ).toBe(
			'Hello <strong>World</strong>'
		);
	} );
} );
