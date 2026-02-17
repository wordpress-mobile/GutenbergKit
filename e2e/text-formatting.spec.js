/**
 * External dependencies
 */
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import EditorPage from './editor-page';

test.describe( 'Text Formatting', () => {
	test( 'should type text into a new paragraph block', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.clickBlockAppender();
		await page.keyboard.type( 'Hello World' );

		const blocks = await editor.getBlocks();
		expect( blocks ).toHaveLength( 1 );
		expect( blocks[ 0 ].attributes.content ).toBe( 'Hello World' );
	} );

	test( 'should apply bold formatting', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.clickBlockAppender();
		await page.keyboard.type( 'Bold text' );
		await page.keyboard.press( 'ControlOrMeta+a' );
		await page.keyboard.press( 'ControlOrMeta+b' );

		const blocks = await editor.getBlocks();
		expect( blocks[ 0 ].attributes.content ).toBe(
			'<strong>Bold text</strong>'
		);
	} );

	test( 'should apply italic formatting', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.clickBlockAppender();
		await page.keyboard.type( 'Italic text' );
		await page.keyboard.press( 'ControlOrMeta+a' );
		await page.keyboard.press( 'ControlOrMeta+i' );

		const blocks = await editor.getBlocks();
		expect( blocks[ 0 ].attributes.content ).toBe( '<em>Italic text</em>' );
	} );

	test( 'should apply combined formatting (bold + italic)', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.clickBlockAppender();
		await page.keyboard.type( 'Styled text' );
		await page.keyboard.press( 'ControlOrMeta+a' );
		await page.keyboard.press( 'ControlOrMeta+b' );
		await page.keyboard.press( 'ControlOrMeta+i' );

		const blocks = await editor.getBlocks();
		expect( blocks[ 0 ].attributes.content ).toBe(
			'<strong><em>Styled text</em></strong>'
		);
	} );
} );
