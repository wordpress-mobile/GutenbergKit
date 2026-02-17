/**
 * External dependencies
 */
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import EditorPage from './editor-page';

/**
 * Set the text alignment on the currently selected paragraph block.
 *
 * Opens the "Align text" dropdown from the block toolbar and clicks the
 * requested alignment option.
 *
 * @param {import('@playwright/test').Page} page      Playwright page object.
 * @param {string}                          alignment 'left', 'center', or 'right'.
 */
async function setAlignment( page, alignment ) {
	await page
		.getByRole( 'button', { name: 'Align text', exact: true } )
		.click();
	await page
		.getByRole( 'menuitemradio', { name: `Align text ${ alignment }` } )
		.click();
}

// Skip: The paragraph alignment control requires theme.json typography.textAlign
// support, which is not available in GutenbergKit's dev-mode environment.
// eslint-disable-next-line playwright/no-skipped-test
test.describe.skip( 'Text Alignment', () => {
	test( 'should set paragraph alignment to center', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.clickBlockAppender();
		await page.keyboard.type( 'Centered text' );

		await setAlignment( page, 'center' );

		const blocks = await editor.getBlocks();
		expect( blocks[ 0 ].attributes.style?.typography?.textAlign ).toBe(
			'center'
		);
	} );

	test( 'should set paragraph alignment to right', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.clickBlockAppender();
		await page.keyboard.type( 'Right-aligned text' );

		await setAlignment( page, 'right' );

		const blocks = await editor.getBlocks();
		expect( blocks[ 0 ].attributes.style?.typography?.textAlign ).toBe(
			'right'
		);
	} );
} );
