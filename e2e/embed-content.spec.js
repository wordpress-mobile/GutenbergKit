/**
 * External dependencies
 */
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import EditorPage from './editor-page';
import { credentials } from './wp-env-fixtures';

/**
 * Mock oEmbed proxy response for a YouTube video.
 *
 * This is a simplified version of the JSON that WordPress's oEmbed proxy
 * (`/oembed/1.0/proxy`) returns after fetching from YouTube's oEmbed
 * endpoint. Using a mock avoids external network calls to YouTube, which
 * can flake in CI due to rate-limiting or connectivity issues.
 *
 * @type {Object}
 */
const YOUTUBE_OEMBED_RESPONSE = {
	url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
	title: 'Rick Astley - Never Gonna Give You Up',
	html: '<iframe width="200" height="113" src="https://www.youtube.com/embed/dQw4w9WgXcQ?feature=oembed" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen title="Rick Astley - Never Gonna Give You Up"></iframe>',
	author_name: 'Rick Astley',
	author_url: 'https://www.youtube.com/@RickAstleyYT',
	type: 'video',
	height: 113,
	width: 200,
	version: '1.0',
	provider_name: 'YouTube',
	provider_url: 'https://www.youtube.com/',
	thumbnail_url: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
	thumbnail_height: 360,
	thumbnail_width: 480,
};

/**
 * Intercept the WordPress oEmbed proxy endpoint and return mocked responses.
 *
 * Routes matching the wp-env REST API oEmbed proxy URL are intercepted.
 * YouTube URLs receive a canned successful response; all other URLs
 * receive a 404 (matching WordPress behavior for non-embeddable URLs).
 *
 * @param {import('@playwright/test').Page} page Playwright page.
 */
async function mockOembedProxy( page ) {
	const apiBase = credentials.siteApiRoot;
	await page.route( `${ apiBase }oembed/1.0/proxy**`, ( route ) => {
		const url = new URL( route.request().url() );
		const embedUrl = url.searchParams.get( 'url' ) || '';
		const embedHostname = URL.canParse( embedUrl )
			? new URL( embedUrl ).hostname
			: '';

		if ( /^(www\.)?youtube\.com$/.test( embedHostname ) ) {
			return route.fulfill( {
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify( YOUTUBE_OEMBED_RESPONSE ),
			} );
		}

		return route.fulfill( {
			status: 404,
			contentType: 'application/json',
			body: JSON.stringify( {
				code: 'oembed_invalid_url',
				message: 'Not Found',
				data: { status: 404 },
			} ),
		} );
	} );
}

test.describe( 'Embedded Content', () => {
	test( 'should insert an embed block with a YouTube URL', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await mockOembedProxy( page );
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
		await mockOembedProxy( page );
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
