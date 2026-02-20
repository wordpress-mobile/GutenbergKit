/**
 * External dependencies
 */
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import EditorPage from './editor-page';

test.describe( 'Text Alignment (F.1)', () => {
	test( 'should align a paragraph block to center', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.clickBlockAppender();
		await page.keyboard.type( 'Centered text' );
		await editor.setTextAlignment( 'Align text center' );

		const blocks = await editor.getBlocks();
		expect( blocks[ 0 ].attributes.style.typography.textAlign ).toBe(
			'center'
		);
	} );

	test( 'should align a paragraph block to right', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.clickBlockAppender();
		await page.keyboard.type( 'Right-aligned text' );
		await editor.setTextAlignment( 'Align text right' );

		const blocks = await editor.getBlocks();
		expect( blocks[ 0 ].attributes.style.typography.textAlign ).toBe(
			'right'
		);
	} );

	test( 'should set textAlign on a verse block', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.insertBlock( 'core/verse' );
		const verseInput = page.locator(
			'pre[aria-label="Block: Verse"][contenteditable="true"]'
		);
		await verseInput.click();
		await page.keyboard.type( 'A verse line' );

		await editor.setTextAlignment( 'Align text center' );

		const textAlign = await editor.getBlockAttribute( 0, 'textAlign' );
		expect( textAlign ).toBe( 'center' );
	} );
} );
