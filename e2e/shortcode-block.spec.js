/**
 * External dependencies
 */
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import { setupEditor, getBlocks } from './editor-setup';

test.describe( 'Shortcode Block', () => {
	test( 'should insert a shortcode block and type a shortcode string', async ( {
		page,
	} ) => {
		await setupEditor( page );

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
		const blocks = await getBlocks( page );
		expect( blocks ).toHaveLength( 1 );
		expect( blocks[ 0 ].name ).toBe( 'core/shortcode' );
		expect( blocks[ 0 ].attributes.text ).toBe(
			'[display-posts orderby="date"]'
		);
	} );
} );
