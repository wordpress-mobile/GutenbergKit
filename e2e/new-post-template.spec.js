import { test, expect } from '@playwright/test';
import EditorPage from './editor-page';

/** A new post of the type `wp-env` registers with a block template. */
const NEW_TEMPLATED_POST = {
	id: -1,
	type: 'templated_post',
	restBase: 'templated-posts',
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
		expect( blocks[ 0 ].attributes.content ).toBe(
			'Prefilled heading from the template'
		);
		expect( blocks[ 1 ].attributes.placeholder ).toBe(
			'Placeholder paragraph from the template'
		);

		const state = await page.evaluate( () => {
			const editorSelect = window.wp.data.select( 'core/editor' );
			return {
				isNew: editorSelect.isEditedPostNew(),
				status: editorSelect.getEditedPostAttribute( 'status' ),
			};
		} );
		expect( state ).toEqual( { isNew: true, status: 'auto-draft' } );
	} );

	test( 'does not report an untouched template as a change', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup( { post: NEW_TEMPLATED_POST, preloadData: {} } );

		const { content, changed } = await page.evaluate( () =>
			window.editor.getTitleAndContent()
		);
		expect( content ).toContain( 'Prefilled heading from the template' );
		expect( changed ).toBe( false );
	} );

	test( "locks the post type's template", async ( { page } ) => {
		await page.route(
			/\/wp\/v2\/types\/templated_post\b/,
			async ( route ) => {
				const response = await route.fetch();
				const body = await response.json();
				await route.fulfill( {
					response,
					json: { ...body, template_lock: 'all' },
				} );
			}
		);

		const editor = new EditorPage( page );
		await editor.setup( { post: NEW_TEMPLATED_POST, preloadData: {} } );

		await expect
			.poll( () =>
				page.evaluate( () =>
					window.wp.data
						.select( 'core/block-editor' )
						.getTemplateLock()
				)
			)
			.toBe( 'all' );
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

	test( 'keeps the title of a new post that has one', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup( {
			post: { ...NEW_TEMPLATED_POST, title: 'Trip notes' },
			preloadData: {},
		} );

		await expect(
			page.getByRole( 'textbox', { name: 'Add title' } )
		).toHaveText( 'Trip notes' );
		expect( await editor.getBlocks() ).toEqual( [] );
	} );
} );
