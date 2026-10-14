import { test, expect } from '@playwright/test';
import EditorPage from './editor-page';

/** A new post of the type `wp-env` registers with a block template. */
const NEW_TEMPLATED_POST = {
	id: -1,
	type: 'gbk_templated',
	restBase: 'gbk-templated',
	restNamespace: 'wp/v2',
	status: 'draft',
	title: '',
	content: '',
};

test.describe( 'New post template', () => {
	test( 'applies the post type template to an empty new post', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		// An empty preload makes the editor request the post types, as hosts
		// preload the site's real ones.
		await editor.setup( { post: NEW_TEMPLATED_POST, preloadData: {} } );

		const blocks = await editor.getBlocks();
		expect( blocks.map( ( { name } ) => name ) ).toEqual( [
			'core/heading',
			'core/paragraph',
		] );
		expect( blocks[ 0 ].attributes.content ).toBe( 'Template heading' );

		const state = await page.evaluate( () => {
			const editorSelect = window.wp.data.select( 'core/editor' );
			return {
				isNew: editorSelect.isEditedPostNew(),
				status: editorSelect.getEditedPostAttribute( 'status' ),
			};
		} );
		expect( state ).toEqual( { isNew: true, status: 'auto-draft' } );
	} );

	test( 'keeps the content of a new post that has some', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup( {
			post: {
				...NEW_TEMPLATED_POST,
				content:
					'<!-- wp:paragraph -->\n<p>Local draft</p>\n<!-- /wp:paragraph -->',
			},
			preloadData: {},
		} );

		const blocks = await editor.getBlocks();
		expect( blocks.map( ( { name } ) => name ) ).toEqual( [
			'core/paragraph',
		] );
		await expect( page.getByText( 'Local draft' ) ).toBeVisible();
	} );
} );
