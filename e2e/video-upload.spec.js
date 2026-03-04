/**
 * External dependencies
 */
import path from 'node:path';
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import EditorPage from './editor-page';
import { uploadsPathPattern } from './wp-env-fixtures';

const TEST_VIDEO = path.resolve( import.meta.dirname, 'assets/test-video.mp4' );

test.describe( 'Video Upload', () => {
	test( 'should upload a video via the Video block', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.insertBlock( 'core/video' );

		// Use the "Upload" button which triggers a file input.
		const fileChooserPromise = page.waitForEvent( 'filechooser' );
		await page
			.getByRole( 'button', { name: 'Upload', exact: true } )
			.click();
		const fileChooser = await fileChooserPromise;
		await fileChooser.setFiles( TEST_VIDEO );

		// Wait for the upload to complete (block gets a numeric media ID).
		const attrs = await editor.waitForMediaUpload( 0 );
		expect( attrs.id ).toBeGreaterThan( 0 );
		expect( attrs.src ).toContain( uploadsPathPattern );

		// Verify the video element is rendered.
		await expect( page.locator( '.wp-block-video video' ) ).toBeVisible();
	} );
} );
