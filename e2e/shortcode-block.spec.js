/**
 * External dependencies
 */
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import EditorPage from './editor-page';

test.describe( 'Shortcode Block', () => {
	test( 'should insert a shortcode block and type a shortcode string', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		// Insert a Shortcode block via the data store.
		await page.evaluate( () => {
			const block = window.wp.blocks.createBlock( 'core/shortcode' );
			window.wp.data.dispatch( 'core/block-editor' ).insertBlock( block );
		} );

		// Wait for the shortcode block to appear.
		const shortcodeInput = page.locator(
			'textarea[aria-label="Shortcode text"]'
		);
		await expect( shortcodeInput ).toBeVisible();

		// Type the shortcode text.
		await shortcodeInput.fill( '[display-posts orderby="date"]' );

		// Verify the block data in the store.
		const blocks = await editor.getBlocks();
		expect( blocks ).toHaveLength( 1 );
		expect( blocks[ 0 ].name ).toBe( 'core/shortcode' );
		expect( blocks[ 0 ].attributes.text ).toBe(
			'[display-posts orderby="date"]'
		);
	} );
} );
