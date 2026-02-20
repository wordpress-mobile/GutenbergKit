/**
 * External dependencies
 */
import path from 'node:path';
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import EditorPage from './editor-page';

const TEST_IMAGE = path.resolve( import.meta.dirname, 'assets/test-image.png' );

test.describe( 'Image Upload (S.2)', () => {
	test( 'should upload an image via the Image block', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.insertBlock( 'core/image' );

		// Use the "Upload" button which triggers a file input.
		const fileChooserPromise = page.waitForEvent( 'filechooser' );
		await page
			.getByRole( 'button', { name: 'Upload', exact: true } )
			.click();
		const fileChooser = await fileChooserPromise;
		await fileChooser.setFiles( TEST_IMAGE );

		// Wait for the upload to complete (block gets a numeric media ID).
		const attrs = await editor.waitForMediaUpload( 0 );
		expect( attrs.id ).toBeGreaterThan( 0 );
		expect( attrs.url ).toContain( 'localhost:8888' );

		// Verify the image element is rendered.
		await expect( page.locator( '.wp-block-image img' ) ).toBeVisible();
	} );
} );
