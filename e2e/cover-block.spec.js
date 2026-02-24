/**
 * External dependencies
 */
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import EditorPage from './editor-page';

test.describe( 'Cover Block', () => {
	test( 'should insert a cover block and select a background color', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.insertBlock( 'core/cover' );

		// The Cover block placeholder should be visible.
		const coverBlock = page.locator( '.wp-block-cover' );
		await expect( coverBlock ).toBeVisible();

		// Select a color from the overlay color palette in the placeholder.
		const colorPalette = page.getByRole( 'group', {
			name: 'Overlay color',
		} );
		await expect( colorPalette ).toBeVisible();
		await colorPalette.getByRole( 'button', { name: 'Black' } ).click();

		// After selecting a color, the Cover block transitions from its
		// placeholder state to a full block with an inner paragraph.
		const innerParagraph = page.getByRole( 'document', {
			name: /start writing/,
		} );
		await expect( innerParagraph ).toBeVisible();

		// Verify the block structure in the data store.
		const blocks = await editor.getBlocks();
		expect( blocks ).toHaveLength( 1 );
		expect( blocks[ 0 ].name ).toBe( 'core/cover' );
		expect( blocks[ 0 ].attributes.overlayColor ).toBe( 'black' );

		const innerBlocks = blocks[ 0 ].innerBlocks;
		expect( innerBlocks ).toHaveLength( 1 );
		expect( innerBlocks[ 0 ].name ).toBe( 'core/paragraph' );
	} );
} );
