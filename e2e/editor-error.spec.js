/**
 * External dependencies
 */
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import EditorPage from './editor-page';

test.describe( 'Editor Error Handling', () => {
	test( 'should handle raw HTML without block delimiters gracefully', async ( {
		page,
	} ) => {
		// Raw HTML without Gutenberg block comment delimiters maps to the
		// Classic Editor (core/freeform) block. GutenbergKit does not register
		// that block, so Gutenberg shows it as core/missing instead.
		const editor = new EditorPage( page );
		await editor.setup( {
			post: {
				id: 1,
				type: 'post',
				status: 'draft',
				title: '',
				content: '<p>Some text without delimiters</p>',
			},
		} );

		const blocks = await editor.getBlocks();
		expect( blocks ).toHaveLength( 1 );
		expect( blocks[ 0 ].name ).toBe( 'core/missing' );
	} );

	test( 'should show error UI when GBKit is missing without dev mode', async ( {
		page,
	} ) => {
		// Navigate without dev_mode and without injecting window.GBKit.
		// The bridge waits 3s then rejects, triggering the error screen.
		await page.goto( '/' );

		const errorHeading = page.getByRole( 'heading', {
			name: 'Editor load error',
		} );
		await expect( errorHeading ).toBeVisible( { timeout: 10_000 } );

		await expect(
			page.getByText(
				'Sorry, loading the editor failed. Please try again.'
			)
		).toBeVisible();
	} );

	test( 'should convert unregistered block types to missing blocks', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup( {
			post: {
				id: 1,
				type: 'post',
				status: 'draft',
				title: '',
				content:
					'<!-- wp:nonexistent/block -->\n<p>Unknown block</p>\n<!-- /wp:nonexistent/block -->',
			},
		} );

		const blocks = await editor.getBlocks();
		expect( blocks ).toHaveLength( 1 );
		expect( blocks[ 0 ].name ).toBe( 'core/missing' );
		expect( blocks[ 0 ].attributes.originalName ).toBe(
			'nonexistent/block'
		);

		await expect(
			page.getByText( 'Your site doesn\u2019t include support for' )
		).toBeVisible();
	} );

	test( 'should load editor without error when plugins enabled but no assets provided', async ( {
		page,
	} ) => {
		// Enable plugins without providing editorAssets in the config.
		// The editor should load normally without showing an error notice.
		const editor = new EditorPage( page );
		await editor.setup( {
			post: {
				id: 1,
				type: 'post',
				status: 'draft',
				title: '',
				content: '',
			},
			plugins: true,
		} );

		// Editor should be functional — no plugin load failure notice.
		await expect(
			page.locator( '.gutenberg-kit-visual-editor' )
		).toBeVisible();

		await expect(
			page.getByText(
				'Loading plugins failed, using default editor configuration.'
			)
		).toBeHidden();
	} );
} );
