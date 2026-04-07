/**
 * External dependencies
 */
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import EditorPage from './editor-page';

test.describe( 'getTitleAndContent', () => {
	test( 'returns correct title and content before any edits', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup( {
			post: {
				id: 1,
				type: 'post',
				status: 'draft',
				title: 'Initial Title',
				content:
					'<!-- wp:paragraph -->\n<p>Hello</p>\n<!-- /wp:paragraph -->',
			},
		} );

		const result = await editor.getTitleAndContent();

		expect( typeof result.title ).toBe( 'string' );
		expect( typeof result.content ).toBe( 'string' );
		expect( result.title ).toBe( 'Initial Title' );
		expect( result.content ).toBe(
			'<!-- wp:paragraph -->\n<p>Hello</p>\n<!-- /wp:paragraph -->'
		);
		expect( result.changed ).toBe( false );
	} );

	test( 'returns plain strings after editing the title', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup( {
			post: {
				id: 1,
				type: 'post',
				status: 'draft',
				title: 'Original',
				content: '',
			},
		} );

		const titleInput = page.getByRole( 'textbox', {
			name: 'Add title',
		} );
		await titleInput.click();
		await page.keyboard.press( 'ControlOrMeta+a' );
		await page.keyboard.type( 'Updated Title' );

		const result = await editor.getTitleAndContent();

		expect( typeof result.title ).toBe( 'string' );
		expect( result.title ).toBe( 'Updated Title' );
		expect( result.changed ).toBe( true );
	} );

	test( 'returns plain strings after editing content', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup( {
			post: {
				id: 1,
				type: 'post',
				status: 'draft',
				title: 'Title',
				content: '',
			},
		} );

		await editor.clickBlockAppender();
		await page.keyboard.type( 'New paragraph' );

		const result = await editor.getTitleAndContent();

		expect( typeof result.title ).toBe( 'string' );
		expect( typeof result.content ).toBe( 'string' );
		expect( result.title ).toBe( 'Title' );
		expect( result.content ).toContain( 'New paragraph' );
		expect( result.changed ).toBe( true );
	} );

	test( 'returns plain strings with empty initial state', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		const result = await editor.getTitleAndContent();

		expect( typeof result.title ).toBe( 'string' );
		expect( typeof result.content ).toBe( 'string' );
		expect( result.title ).toBe( '' );
		expect( result.content ).toBe( '' );
		expect( result.changed ).toBe( false );
	} );

	test( 'returns plain strings when data store title is a {raw, rendered} object', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup( {
			post: {
				id: 1,
				type: 'post',
				status: 'draft',
				title: 'Initial Title',
				content: '',
			},
		} );

		// Inject an object-shaped title edit via editEntityRecord.
		// This simulates the Gutenberg data store bug where
		// getEditedPostAttribute bypasses getPostRawValue normalization
		// for values in the edits layer.
		await page.evaluate( () => {
			window.wp.data
				.dispatch( 'core' )
				.editEntityRecord( 'postType', 'post', 1, {
					title: {
						raw: 'Object Title',
						rendered: '<b>Object Title</b>',
					},
				} );
		} );

		const result = await editor.getTitleAndContent();

		expect( typeof result.title ).toBe( 'string' );
		expect( result.title ).toBe( 'Object Title' );
		expect( result.changed ).toBe( true );

		// Second call should report no further changes.
		const second = await editor.getTitleAndContent();
		expect( second.changed ).toBe( false );
	} );

	test( 'returns plain strings when data store content is a {raw, rendered} object', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup( {
			post: {
				id: 1,
				type: 'post',
				status: 'draft',
				title: 'Title',
				content: '',
			},
		} );

		await page.evaluate( () => {
			window.wp.data
				.dispatch( 'core' )
				.editEntityRecord( 'postType', 'post', 1, {
					content: {
						raw: '<!-- wp:paragraph --><p>Test</p><!-- /wp:paragraph -->',
						rendered: '<p>Test</p>',
					},
				} );
		} );

		const result = await editor.getTitleAndContent();

		expect( typeof result.content ).toBe( 'string' );
		expect( result.content ).toContain(
			'<!-- wp:paragraph --><p>Test</p><!-- /wp:paragraph -->'
		);
		expect( result.changed ).toBe( true );

		// Second call should report no further changes.
		const second = await editor.getTitleAndContent();
		expect( second.changed ).toBe( false );
	} );
} );
