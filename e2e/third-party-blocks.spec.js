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

test.describe( 'Third-Party Blocks', () => {
	test( 'should load and insert a third-party block type', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup( { plugins: true } );

		// Verify the Jetpack tiled-gallery block type is registered.
		const isRegistered = await page.evaluate( () =>
			Boolean( window.wp.blocks.getBlockType( 'jetpack/tiled-gallery' ) )
		);
		expect( isRegistered ).toBe( true );

		await editor.insertBlock( 'jetpack/tiled-gallery' );

		const blocks = await editor.getBlocks();
		expect( blocks ).toHaveLength( 1 );
		expect( blocks[ 0 ].name ).toBe( 'jetpack/tiled-gallery' );
	} );

	test( 'should upload images to the Tiled Gallery block', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup( { plugins: true } );

		await editor.insertBlock( 'jetpack/tiled-gallery' );

		// Use the "Upload" button to trigger the file input.
		const fileChooserPromise = page.waitForEvent( 'filechooser' );
		await page
			.getByRole( 'button', { name: 'Upload', exact: true } )
			.click();
		const fileChooser = await fileChooserPromise;
		await fileChooser.setFiles( [ TEST_IMAGE_1, TEST_IMAGE_2 ] );

		// Wait for both images to upload by checking the gallery's `ids` attribute.
		// The Tiled Gallery stores images as attributes (not inner blocks).
		// `ids` contains null entries while uploads are in-flight and positive
		// integers once the uploads complete.
		await page.waitForFunction(
			() => {
				const blocks = window.wp.data
					.select( 'core/block-editor' )
					.getBlocks();
				const gallery = blocks[ 0 ];
				return (
					gallery?.attributes?.ids?.length === 2 &&
					gallery.attributes.ids.every( ( id ) => id > 0 )
				);
			},
			null,
			{ timeout: 30_000 }
		);

		const blocks = await editor.getBlocks();
		const gallery = blocks[ 0 ];
		expect( gallery.name ).toBe( 'jetpack/tiled-gallery' );
		expect( gallery.attributes.ids ).toHaveLength( 2 );
		expect( gallery.attributes.images ).toHaveLength( 2 );
	} );
} );
