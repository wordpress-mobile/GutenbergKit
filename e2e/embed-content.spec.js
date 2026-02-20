/**
 * External dependencies
 */
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import EditorPage from './editor-page';

test.describe( 'Embedded Content (F.2)', () => {
	test( 'should insert an embed block with a YouTube URL', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.insertBlock( 'core/embed' );

		// Type a YouTube URL into the embed URL input.
		const urlInput = page.getByRole( 'textbox', {
			name: 'Embed URL',
		} );
		await expect( urlInput ).toBeVisible();
		await urlInput.fill( 'https://www.youtube.com/watch?v=dQw4w9WgXcQ' );
		await page.keyboard.press( 'Enter' );

		// Wait for the oEmbed proxy to resolve — the block should get
		// a `url` attribute and the embed preview should render.
		await page.waitForFunction(
			() => {
				const blocks = window.wp.data
					.select( 'core/block-editor' )
					.getBlocks();
				const embed = blocks[ 0 ];
				return (
					embed?.attributes?.url &&
					embed?.attributes?.providerNameSlug
				);
			},
			{ timeout: 30_000 }
		);

		const blocks = await editor.getBlocks();
		expect( blocks[ 0 ].attributes.url ).toContain( 'youtube.com' );
		expect( blocks[ 0 ].attributes.providerNameSlug ).toBe( 'youtube' );
	} );

	test( 'should show a fallback link for a non-embeddable URL', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.insertBlock( 'core/embed' );

		const urlInput = page.getByRole( 'textbox', {
			name: 'Embed URL',
		} );
		await expect( urlInput ).toBeVisible();
		await urlInput.fill( 'https://example.com/not-embeddable' );
		await page.keyboard.press( 'Enter' );

		// Wait for the embed to resolve (or fall back).
		// The block should still render with the URL attribute.
		await page.waitForFunction(
			() => {
				const blocks = window.wp.data
					.select( 'core/block-editor' )
					.getBlocks();
				return blocks[ 0 ]?.attributes?.url;
			},
			{ timeout: 30_000 }
		);

		const blocks = await editor.getBlocks();
		expect( blocks[ 0 ].attributes.url ).toContain(
			'example.com/not-embeddable'
		);
	} );
} );
