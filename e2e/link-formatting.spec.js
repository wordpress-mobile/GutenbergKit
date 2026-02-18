/**
 * External dependencies
 */
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import EditorPage from './editor-page';

test.describe( 'Link Formatting', () => {
	test( 'should add a link to selected text', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.clickBlockAppender();
		await page.keyboard.type( 'Link me' );
		await editor.selectAll();
		await editor.insertLink( 'https://example.com' );

		const blocks = await editor.getBlocks();
		expect( blocks[ 0 ].attributes.content ).toBe(
			'<a href="https://example.com">Link me</a>'
		);
	} );

	test( 'should add a link to a partial text selection', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.clickBlockAppender();
		await page.keyboard.type( 'Hello World' );

		// Select only "World" (positions 6–11).
		await editor.moveCaretTo( 6 );
		for ( let i = 0; i < 5; i++ ) {
			await page.keyboard.press( 'Shift+ArrowRight' );
		}

		await editor.insertLink( 'https://example.com' );

		const blocks = await editor.getBlocks();
		expect( blocks[ 0 ].attributes.content ).toBe(
			'Hello <a href="https://example.com">World</a>'
		);
	} );

	test( 'should open link popover UI', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.clickBlockAppender();
		await page.keyboard.type( 'Test' );
		await editor.selectAll();
		await page.getByRole( 'button', { name: 'Link' } ).click();

		await expect(
			page.getByRole( 'combobox', { name: 'Search or type URL' } )
		).toBeVisible();
	} );
} );
