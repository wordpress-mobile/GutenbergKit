/**
 * Covers the behavior each patch in `patches/` exists for. A patch can apply
 * cleanly to a new package version yet stop having an effect, so these tests
 * check the patched behavior rather than the patched code.
 */
import fs from 'node:fs';
import path from 'node:path';
import { test, expect } from '@playwright/test';
import EditorPage from './editor-page';

const PHONE_VIEWPORT = { width: 390, height: 844 };

const TEST_IMAGE_URL = `data:image/png;base64,${ fs
	.readFileSync(
		path.resolve( import.meta.dirname, 'assets/test-image.png' )
	)
	.toString( 'base64' ) }`;

test.describe( '@wordpress/block-editor patch', () => {
	test( 'opens the inserter when the editor store requests it', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		// "Browse all" in the quick inserter opens the inserter this way.
		await page.evaluate( () =>
			window.wp.data.dispatch( 'core/editor' ).setIsInserterOpened( true )
		);

		await expect(
			page.getByRole( 'tab', { name: 'Blocks', exact: true } )
		).toBeVisible();
	} );

	test( 'exposes the inserter as a modal dialog', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await openInserter( page );

		await expect( page.getByRole( 'dialog' ) ).toHaveAttribute(
			'aria-modal',
			'true'
		);
	} );

	test( 'lists patterns in the inserter', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await openInserter( page );
		await inserterTab( page, 'Patterns' ).click();

		await expect(
			page
				.getByRole( 'tabpanel', { name: 'Patterns' } )
				.getByRole( 'tab', { name: 'All', exact: true } )
		).toBeVisible();
	} );

	test( 'lists media categories in the inserter', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await openInserter( page );
		await inserterTab( page, 'Media' ).click();

		// The tab opens the first category with media, e.g., Openverse on an
		// empty site, and each category has a search field.
		await expect(
			page
				.getByRole( 'tabpanel', { name: 'Media' } )
				.getByRole( 'searchbox' )
		).toBeVisible();
	} );

	test.describe( 'on a touch device', () => {
		test.use( {
			hasTouch: true,
			isMobile: true,
			viewport: PHONE_VIEWPORT,
		} );

		test( 'does not show the insertion point when an inserter item is hovered', async ( {
			page,
		} ) => {
			const editor = new EditorPage( page );
			await editor.setup( {
				post: {
					content:
						'<!-- wp:paragraph -->\n<p>First</p>\n<!-- /wp:paragraph -->',
				},
			} );

			await openInserter( page );
			// A tap fires mouse events too, so touch devices hover the item
			// before activating it.
			await page.getByRole( 'option', { name: 'Paragraph' } ).hover();

			const isInsertionPointVisible = await page.evaluate( () =>
				window.wp.data
					.select( 'core/block-editor' )
					.isBlockInsertionPointVisible()
			);
			expect( isInsertionPointVisible ).toBe( false );
		} );
	} );
} );

test.describe( '@wordpress/block-library patch', () => {
	test.describe( 'on a phone-sized viewport', () => {
		test.use( { viewport: PHONE_VIEWPORT } );

		test( 'allows resizing an image', async ( { page } ) => {
			const editor = new EditorPage( page );
			await editor.setup();

			await editor.insertBlock( 'core/image', { url: TEST_IMAGE_URL } );
			await editor.selectBlock( 0 );

			await expect(
				page.locator( '.components-resizable-box__handle' ).first()
			).toBeVisible();
		} );
	} );

	for ( const { name, content, selector } of [
		{
			name: 'Paragraph',
			content:
				'<!-- wp:paragraph -->\n<p>First</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:paragraph -->\n<p>Second</p>\n<!-- /wp:paragraph -->',
			selector: '[data-type="core/paragraph"]',
		},
		{
			name: 'Heading',
			content:
				'<!-- wp:heading -->\n<h2 class="wp-block-heading">First</h2>\n<!-- /wp:heading -->\n\n<!-- wp:heading -->\n<h2 class="wp-block-heading">Second</h2>\n<!-- /wp:heading -->',
			selector: '[data-type="core/heading"]',
		},
		{
			name: 'List Item',
			content:
				'<!-- wp:list -->\n<ul class="wp-block-list"><!-- wp:list-item -->\n<li>First</li>\n<!-- /wp:list-item -->\n\n<!-- wp:list-item -->\n<li>Second</li>\n<!-- /wp:list-item --></ul>\n<!-- /wp:list -->',
			selector: '[data-type="core/list-item"] [contenteditable="true"]',
		},
	] ) {
		// An editable writing flow wrapper takes focus from the block, which
		// breaks caret placement on iOS.
		test( `keeps focus in a selected ${ name } block`, async ( {
			page,
		} ) => {
			const editor = new EditorPage( page );
			await editor.setup( { post: { content } } );

			const block = page.locator( selector ).first();
			await block.click();

			await expect( block ).toBeFocused();
			const hasEditableAncestor = await block.evaluate(
				( element ) =>
					!! element.parentElement.closest(
						'[contenteditable="true"]'
					)
			);
			expect( hasEditableAncestor ).toBe( false );
		} );
	}
} );

test.describe( 'mousetrap patch', () => {
	// No bundled package binds global shortcuts, but plugins can through
	// `window.wp.compose`.
	test( 'fires global keyboard shortcuts inside editable fields', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await page.evaluate( () => {
			const { createElement, createRoot } = window.wp.element;
			const { useKeyboardShortcut } = window.wp.compose;

			function GlobalShortcut() {
				useKeyboardShortcut(
					'mod+shift+alt+j',
					() => {
						window.globalShortcutFired = true;
					},
					{ bindGlobal: true }
				);
				return null;
			}

			createRoot( document.createElement( 'div' ) ).render(
				createElement( GlobalShortcut )
			);
		} );

		await page.getByRole( 'textbox', { name: 'Add title' } ).click();
		await page.keyboard.press( 'ControlOrMeta+Shift+Alt+j' );

		await expect
			.poll( () => page.evaluate( () => window.globalShortcutFired ) )
			.toBe( true );
	} );
} );

/**
 * Open the block inserter from the editor toolbar.
 *
 * @param {import('@playwright/test').Page} page Playwright page object.
 */
async function openInserter( page ) {
	await page
		.locator( '.gutenberg-kit-editor-toolbar' )
		.getByRole( 'button', { name: 'Add block' } )
		.click();
}

/**
 * Locate one of the inserter's top-level tabs.
 *
 * Pattern categories render their own tabs, e.g., "Media", so the locator is
 * scoped to the inserter's tab list.
 *
 * @param {import('@playwright/test').Page} page Playwright page object.
 * @param {string}                          name Tab name.
 * @return {import('@playwright/test').Locator} The tab locator.
 */
function inserterTab( page, name ) {
	return page
		.locator( '.block-editor-tabbed-sidebar__tab' )
		.filter( { hasText: name } );
}
