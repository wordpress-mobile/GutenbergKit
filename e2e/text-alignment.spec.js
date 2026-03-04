/**
 * External dependencies
 */
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import EditorPage from './editor-page';

test.describe( 'Text Alignment', () => {
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
} );
