/**
 * External dependencies
 */
import path from 'node:path';
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import EditorPage from './editor-page';

const TEST_FILE = path.resolve( import.meta.dirname, 'assets/test-file.pdf' );

test.describe( 'File Upload', () => {
	test( 'should upload a file via the File block', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.insertBlock( 'core/file' );

		// Use the "Upload" button which triggers a file input.
		const fileChooserPromise = page.waitForEvent( 'filechooser' );
		await page
			.getByRole( 'button', { name: 'Upload', exact: true } )
			.click();
		const fileChooser = await fileChooserPromise;
		await fileChooser.setFiles( TEST_FILE );

		// Wait for the upload to complete (block gets a numeric media ID).
		const attrs = await editor.waitForMediaUpload( 0 );
		expect( attrs.id ).toBeGreaterThan( 0 );
		expect( attrs.href ).toContain( ':8888/wp-content/uploads/' );

		// Verify the filename and download link are rendered.
		await expect(
			page.locator( '.wp-block-file a' ).first()
		).toBeVisible();
		expect( attrs.fileName ).toContain( 'test-file' );
	} );
} );
