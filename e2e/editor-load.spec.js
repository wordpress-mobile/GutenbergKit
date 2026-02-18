/**
 * External dependencies
 */
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import EditorPage from './editor-page';

test.describe( 'Editor Load', () => {
	test( 'should load the editor and reach ready state', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup();

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
			page.getByRole( 'button', { name: 'Add paragraph block' } )
		).toBeAttached();
	} );

	test( 'should display an empty editor with no initial content', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		const blocks = await editor.getBlocks();
		expect( blocks ).toHaveLength( 0 );
	} );

	test( 'should load the editor with initial content', async ( { page } ) => {
		const contentHtml =
			'<!-- wp:paragraph -->\n<p>Hello from E2E</p>\n<!-- /wp:paragraph -->';

		const editor = new EditorPage( page );
		await editor.setup( {
			post: {
				id: 1,
				type: 'post',
				status: 'draft',
				title: '',
				content: contentHtml,
			},
		} );

		const blocks = await editor.getBlocks();
		expect( blocks ).toHaveLength( 1 );
		expect( blocks[ 0 ].name ).toBe( 'core/paragraph' );

		await expect( page.getByText( 'Hello from E2E' ) ).toBeVisible();
	} );
} );
