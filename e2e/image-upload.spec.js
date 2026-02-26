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

test.describe( 'Image Upload', () => {
	test( 'should upload an image via the Image block', async ( { page } ) => {
		// Log all network requests to wp-env for debugging upload issues in CI.
		page.on( 'request', ( request ) => {
			const url = request.url();
			if ( url.includes( 'localhost:8888' ) ) {
				// eslint-disable-next-line no-console
				console.log(
					`[REQ] ${ request.method() } ${ url } headers=${ JSON.stringify(
						Object.fromEntries(
							Object.entries( request.headers() ).filter(
								( [ k ] ) =>
									[
										'content-type',
										'authorization',
										'origin',
									].includes( k )
							)
						)
					) }`
				);
			}
		} );
		page.on( 'response', ( response ) => {
			const url = response.url();
			if ( url.includes( 'localhost:8888' ) ) {
				// eslint-disable-next-line no-console
				console.log(
					`[RES] ${ response.status() } ${ url } headers=${ JSON.stringify(
						Object.fromEntries(
							Object.entries( response.headers() ).filter(
								( [ k ] ) =>
									[
										'access-control-allow-origin',
										'access-control-allow-headers',
										'access-control-allow-methods',
									].includes( k )
							)
						)
					) }`
				);
			}
		} );
		page.on( 'requestfailed', ( request ) => {
			const url = request.url();
			if ( url.includes( 'localhost:8888' ) ) {
				// eslint-disable-next-line no-console
				console.log(
					`[FAIL] ${ request.method() } ${ url } failure=${
						request.failure()?.errorText
					}`
				);
			}
		} );

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
