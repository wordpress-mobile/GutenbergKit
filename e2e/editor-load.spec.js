/**
 * External dependencies
 */
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import { setupEditor, getBlocks } from './editor-setup';

test.describe( 'Editor Load', () => {
	test( 'should load the editor and reach ready state', async ( {
		page,
	} ) => {
		await setupEditor( page );

		await expect(
			page.locator( '.gutenberg-kit-visual-editor' )
		).toBeVisible();

		await expect(
			page.locator( '.editor-visual-editor__post-title-wrapper' )
		).toBeVisible();

		await expect(
			page.locator( '.block-editor-block-list__layout.is-root-container' )
		).toBeVisible();

		await expect(
			page.locator( '.gutenberg-kit-editor-toolbar' )
		).toBeVisible();

		await expect(
			page.locator( 'button.gutenberg-kit-default-block-appender' )
		).toBeAttached();
	} );

	test( 'should display an empty editor with no initial content', async ( {
		page,
	} ) => {
		await setupEditor( page );

		const blocks = await getBlocks( page );
		expect( blocks ).toHaveLength( 0 );
	} );

	test( 'should load the editor with initial content', async ( { page } ) => {
		const contentHtml =
			'<!-- wp:paragraph -->\n<p>Hello from E2E</p>\n<!-- /wp:paragraph -->';

		await setupEditor( page, {
			post: {
				id: 1,
				type: 'post',
				status: 'draft',
				title: '',
				content: contentHtml,
			},
		} );

		const blocks = await getBlocks( page );
		expect( blocks ).toHaveLength( 1 );
		expect( blocks[ 0 ].name ).toBe( 'core/paragraph' );

		await expect( page.getByText( 'Hello from E2E' ) ).toBeVisible();
	} );
} );
