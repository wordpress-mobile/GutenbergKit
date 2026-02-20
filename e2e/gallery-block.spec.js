/**
 * External dependencies
 */
import path from 'node:path';
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import EditorPage from './editor-page';

const TEST_IMAGE_1 = path.resolve(
	import.meta.dirname,
	'assets/test-image.png'
);
const TEST_IMAGE_2 = path.resolve(
	import.meta.dirname,
	'assets/test-image-2.png'
);

test.describe( 'Gallery Block (F.4)', () => {
	test( 'should upload multiple images to a gallery', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.insertBlock( 'core/gallery' );

		// Use the "Upload" button to trigger the file input.
		const fileChooserPromise = page.waitForEvent( 'filechooser' );
		await page
			.getByRole( 'button', { name: 'Upload', exact: true } )
			.click();
		const fileChooser = await fileChooserPromise;
		await fileChooser.setFiles( [ TEST_IMAGE_1, TEST_IMAGE_2 ] );

		// Wait for both images to upload by checking the gallery's inner blocks.
		await page.waitForFunction(
			() => {
				const blocks = window.wp.data
					.select( 'core/block-editor' )
					.getBlocks();
				const gallery = blocks[ 0 ];
				return (
					gallery?.innerBlocks?.length === 2 &&
					gallery.innerBlocks.every(
						( img ) => img.attributes.id > 0
					)
				);
			},
			{ timeout: 30_000 }
		);

		const blocks = await editor.getBlocks();
		const gallery = blocks[ 0 ];
		expect( gallery.name ).toBe( 'core/gallery' );
		expect( gallery.innerBlocks ).toHaveLength( 2 );
		expect( gallery.innerBlocks[ 0 ].name ).toBe( 'core/image' );
		expect( gallery.innerBlocks[ 1 ].name ).toBe( 'core/image' );
	} );

	test( 'should add a caption to an image in the gallery', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.insertBlock( 'core/gallery' );

		// Upload a single image.
		const fileChooserPromise = page.waitForEvent( 'filechooser' );
		await page
			.getByRole( 'button', { name: 'Upload', exact: true } )
			.click();
		const fileChooser = await fileChooserPromise;
		await fileChooser.setFiles( TEST_IMAGE_1 );

		// Wait for the upload to complete.
		await page.waitForFunction(
			() => {
				const blocks = window.wp.data
					.select( 'core/block-editor' )
					.getBlocks();
				const gallery = blocks[ 0 ];
				return (
					gallery?.innerBlocks?.length === 1 &&
					gallery.innerBlocks[ 0 ].attributes.id > 0
				);
			},
			{ timeout: 30_000 }
		);

		// Set a caption on the inner Image block via the data store.
		await page.evaluate( () => {
			const blocks = window.wp.data
				.select( 'core/block-editor' )
				.getBlocks();
			const innerImage = blocks[ 0 ]?.innerBlocks?.[ 0 ];
			if ( innerImage ) {
				window.wp.data
					.dispatch( 'core/block-editor' )
					.updateBlockAttributes( innerImage.clientId, {
						caption: 'Test caption',
					} );
			}
		} );

		// Verify the caption was applied.
		const blocks = await editor.getBlocks();
		const innerImage = blocks[ 0 ].innerBlocks[ 0 ];
		expect( innerImage.attributes.caption ).toBe( 'Test caption' );
	} );
} );
