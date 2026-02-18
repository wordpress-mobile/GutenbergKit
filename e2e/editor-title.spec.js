/**
 * External dependencies
 */
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import EditorPage from './editor-page';

test.describe( 'Editor Title', () => {
	test( 'should display post title input', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await expect(
			page.locator( '.gutenberg-kit-visual-editor__post-title-wrapper' )
		).toBeVisible();
	} );

	test( 'should allow typing in the post title', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		const titleInput = page.getByRole( 'textbox', {
			name: 'Add title',
		} );
		await titleInput.click();
		await page.keyboard.type( 'My Test Post' );

		const title = await page.evaluate( () =>
			window.wp.data
				.select( 'core/editor' )
				.getEditedPostAttribute( 'title' )
		);
		expect( title ).toBe( 'My Test Post' );
	} );

	test( 'should move from title to first block with Enter', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		const titleInput = page.getByRole( 'textbox', {
			name: 'Add title',
		} );
		await titleInput.click();
		await page.keyboard.type( 'Title text' );
		await page.keyboard.press( 'Enter' );

		// A new paragraph block should be created.
		const blocks = await editor.getBlocks();
		expect( blocks ).toHaveLength( 1 );
		expect( blocks[ 0 ].name ).toBe( 'core/paragraph' );
	} );

	test( 'should hide title when hideTitle is configured', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup( {
			post: {
				id: -1,
				type: 'post',
				status: 'draft',
				title: '',
				content: '',
			},
			hideTitle: true,
		} );

		await expect(
			page.locator( '.gutenberg-kit-visual-editor__post-title-wrapper' )
		).toBeHidden();
	} );
} );
