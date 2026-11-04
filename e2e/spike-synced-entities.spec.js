/**
 * Spike S6 (CMM-2560): edits to entities other than the post.
 *
 * Throwaway spec. Each scenario runs twice: with the write guard on (trunk,
 * where the host saves the post natively) and lifted (S1, where core
 * `savePost()` writes). Observations are written to `build/s6/web/`.
 */
/* eslint-disable playwright/no-conditional-in-test, playwright/no-wait-for-timeout, playwright/expect-expect, no-restricted-syntax */
import fs from 'node:fs';
import path from 'node:path';
import { test, expect } from '@playwright/test';
import EditorPage from './editor-page';
import { credentials } from './wp-env-fixtures';

const OUT = path.resolve( import.meta.dirname, '../build/s6/web' );
const API = credentials.siteApiRoot;

const fixtures = {};

async function rest( method, route, body ) {
	const response = await fetch( `${ API }${ route }`, {
		method,
		headers: {
			Authorization: credentials.authHeader,
			'Content-Type': 'application/json',
		},
		body: body ? JSON.stringify( body ) : undefined,
	} );
	const text = await response.text();
	try {
		return JSON.parse( text );
	} catch {
		return text;
	}
}

function record( name, data ) {
	fs.mkdirSync( OUT, { recursive: true } );
	fs.writeFileSync(
		path.join( OUT, `${ name }.json` ),
		JSON.stringify( data, null, 2 )
	);
}

async function openEditor( page, { lift, content } ) {
	await page.addInitScript( () => {
		window.contentChanged = 0;
		window.editorDelegate = {
			onEditorContentChanged: () => window.contentChanged++,
		};
	} );
	// Preload the server's post types, as both hosts do. GBK's built-in
	// fallback has no template part or navigation types.
	const preloadData = {
		'/wp/v2/types?context=view': {
			body: await rest( 'GET', 'wp/v2/types?context=view' ),
		},
		'/wp/v2/types/post?context=edit': {
			body: await rest( 'GET', 'wp/v2/types/post?context=edit' ),
		},
	};
	const editor = new EditorPage( page );
	await editor.setup( {
		preloadData,
		...( content ? { post: { content } } : {} ),
	} );
	await page.waitForFunction( () => window.__s6?.installed );
	await page.evaluate( ( value ) => {
		window.__s6.setLiftGuard( value );
		window.__s6.clearLog();
	}, lift );
	return editor;
}

/**
 * What the host and the editor know after an edit, and the save results.
 *
 * @param {import('@playwright/test').Page} page Playwright page.
 */
async function saveBoth( page ) {
	return page.evaluate( async () => {
		const s6 = window.__s6;
		const before = {
			signals: s6.signals(),
			contentChanged: window.contentChanged,
			dirty: s6.dirty(),
		};
		s6.clearLog();
		const savePost = await s6.savePost();
		return { before, savePost };
	} );
}

test.describe.configure( { mode: 'serial' } );

// Runs first, while the site has no menus, so the fallback has to create one.
test.describe( 'S6: navigation fallback', () => {
	test.afterAll( async () => {
		const items = await rest(
			'GET',
			'wp/v2/navigation?_fields=id&per_page=100&status=publish,draft'
		);
		for ( const item of items ) {
			await rest( 'DELETE', `wp/v2/navigation/${ item.id }?force=true` );
		}
	} );

	test( 'navigation without a menu', async ( { page } ) => {
		await openEditor( page, { lift: false } );
		const before = await rest(
			'GET',
			'wp/v2/navigation?_fields=id,title,status&status=publish,draft'
		);
		const clientId = await page.evaluate( () =>
			window.__s6.insert( 'core/navigation' )
		);
		await page.locator( `[data-block="${ clientId }"]` ).waitFor();
		await page.waitForTimeout( 3000 );
		const log = await page.evaluate( () => ( {
			requests: window.__s6.requests,
			attributes: window.wp.data
				.select( 'core/block-editor' )
				.getBlocks()
				.find( ( b ) => b.name === 'core/navigation' )?.attributes,
			dirty: window.__s6.dirty(),
		} ) );
		const after = await rest(
			'GET',
			'wp/v2/navigation?_fields=id,title,status&status=publish,draft'
		);
		record( 'navigation-fallback', { before, log, after } );
	} );
} );

test.describe( 'S6: other entities', () => {
	test.beforeAll( async () => {
		const synced = await rest( 'POST', 'wp/v2/blocks', {
			title: 'S6 synced',
			status: 'publish',
			content:
				'<!-- wp:paragraph -->\n<p>Synced original</p>\n<!-- /wp:paragraph -->',
		} );
		const overrides = await rest( 'POST', 'wp/v2/blocks', {
			title: 'S6 overrides',
			status: 'publish',
			content:
				'<!-- wp:paragraph {"metadata":{"name":"Body","bindings":{"__default":{"source":"core/pattern-overrides"}}}} -->\n<p>Override me</p>\n<!-- /wp:paragraph -->',
		} );
		const unsynced = await rest( 'POST', 'wp/v2/blocks', {
			title: 'S6 unsynced',
			status: 'publish',
			meta: { wp_pattern_sync_status: 'unsynced' },
			content:
				'<!-- wp:paragraph -->\n<p>Unsynced original</p>\n<!-- /wp:paragraph -->',
		} );
		const menu = await rest( 'POST', 'wp/v2/navigation', {
			title: 'S6 menu',
			status: 'publish',
			content:
				'<!-- wp:navigation-link {"label":"S6 link","url":"https://example.com","kind":"custom"} /-->',
		} );
		Object.assign( fixtures, {
			synced: synced.id,
			overrides: overrides.id,
			unsynced: unsynced.id,
			menu: menu.id,
			settings: await rest(
				'GET',
				'wp/v2/settings?_fields=title,description'
			),
		} );
		record( 'fixtures', fixtures );
	} );

	test.afterAll( async () => {
		// Undo every server effect: settings, template part edits, fixtures,
		// and anything the scenarios created.
		await rest( 'POST', 'wp/v2/settings', fixtures.settings );
		const parts = await rest(
			'GET',
			'wp/v2/template-parts?_fields=id,source&per_page=100'
		);
		for ( const part of parts ) {
			if ( part.source === 'custom' ) {
				await rest(
					'DELETE',
					`wp/v2/template-parts/${ part.id }?force=true`
				);
			}
		}
		for ( const type of [ 'blocks', 'navigation' ] ) {
			const items = await rest(
				'GET',
				`wp/v2/${ type }?_fields=id&per_page=100&status=publish,draft`
			);
			for ( const item of items ) {
				await rest(
					'DELETE',
					`wp/v2/${ type }/${ item.id }?force=true`
				);
			}
		}
	} );

	test( 'inventory', async ( { page } ) => {
		await openEditor( page, { lift: false } );
		await page.waitForFunction(
			() =>
				window.__s6.inventory().inserterSyncedPatterns.length > 0 &&
				window.__s6.inventory().userPatterns.length > 0
		);
		const inventory = await page.evaluate( () => window.__s6.inventory() );
		record( 'inventory', inventory );

		expect( inventory.renderingMode ).toBe( 'post-only' );
		expect( inventory.hasOnNavigateToEntityRecord ).toBe( false );
		expect( inventory.canInsertAtRoot[ 'core/template-part' ] ).toBe(
			false
		);
	} );

	for ( const lift of [ false, true ] ) {
		const mode = lift ? 'lift' : 'trunk';

		test( `synced pattern (${ mode })`, async ( { page } ) => {
			await openEditor( page, { lift } );
			const clientId = await page.evaluate(
				( ref ) => window.__s6.insert( 'core/block', { ref } ),
				fixtures.synced
			);
			const inner = page
				.locator( `[data-block="${ clientId }"]` )
				.getByText( 'Synced original' );
			await inner.waitFor();
			const modes = await page.evaluate(
				( id ) => window.__s6.editingModes( id ),
				clientId
			);
			// Try to edit the pattern's content in place. The inner blocks are
			// inert, so the click lands on the pattern block itself.
			const innerState = await inner.evaluate( ( node ) => ( {
				inert: node.inert,
				contentEditable: node.contentEditable,
			} ) );
			await inner.click( { force: true } );
			await page.keyboard.type( ' EDITED' );
			const afterTyping = await page.evaluate( () => ( {
				blocks: window.wp.data
					.select( 'core/block-editor' )
					.getBlocks()
					.map( ( b ) => b.name ),
				dirty: window.__s6.dirty(),
				text: document.querySelector(
					'.block-library-block__reusable-block-container'
				)?.textContent,
			} ) );
			const saves = await saveBoth( page );
			record( `synced-${ mode }`, {
				modes,
				innerState,
				afterTyping,
				saves,
			} );

			expect(
				afterTyping.dirty.some( ( r ) => r.name === 'wp_block' )
			).toBe( false );
		} );

		test( `pattern overrides (${ mode })`, async ( { page } ) => {
			await openEditor( page, { lift } );
			const clientId = await page.evaluate(
				( ref ) => window.__s6.insert( 'core/block', { ref } ),
				fixtures.overrides
			);
			const inner = page
				.locator( `[data-block="${ clientId }"]` )
				.getByText( 'Override me' );
			await inner.waitFor();
			const modes = await page.evaluate(
				( id ) => window.__s6.editingModes( id ),
				clientId
			);
			await inner.click();
			await page.keyboard.press( 'End' );
			await page.keyboard.type( ' OVERRIDDEN' );
			const text = await page
				.locator( `[data-block="${ clientId }"]` )
				.innerText();
			const attributes = await page.evaluate(
				( id ) =>
					window.wp.data
						.select( 'core/block-editor' )
						.getBlockAttributes( id ),
				clientId
			);
			const saves = await saveBoth( page );
			record( `overrides-${ mode }`, {
				modes,
				text,
				attributes,
				saves,
			} );
		} );

		test( `template part in content (${ mode })`, async ( { page } ) => {
			// The inserter and `insertBlocks` refuse template parts in
			// `post-only` mode, so the post arrives with one, as a post
			// written elsewhere could.
			await openEditor( page, {
				lift,
				content:
					'<!-- wp:template-part {"slug":"footer","theme":"twentytwentyfive"} /-->',
			} );
			const clientId = await page.evaluate( () =>
				window.wp.data
					.select( 'core/block-editor' )
					.getBlockOrder()
					.find(
						( id ) =>
							window.wp.data
								.select( 'core/block-editor' )
								.getBlockName( id ) === 'core/template-part'
					)
			);
			const part = page.locator( `[data-block="${ clientId }"]` );
			const paragraph = part
				.locator( '[data-type="core/paragraph"]' )
				.first();
			const rendered = await paragraph
				.waitFor( { timeout: 8000 } )
				.then( () => true )
				.catch( () => false );
			const modes = await page.evaluate(
				( id ) => window.__s6.editingModes( id ),
				clientId
			);
			const partText = await part.innerText();
			if ( ! rendered ) {
				record( `template-part-${ mode }`, {
					rendered,
					partText,
					modes,
				} );
				return;
			}
			// The first tap selects the part and removes its overlay.
			await part.click( { position: { x: 5, y: 5 } } );
			const overlayAfterSelect = await part.evaluate( ( node ) =>
				node.classList.contains( 'has-block-overlay' )
			);
			const modesAfterSelect = await page.evaluate(
				( id ) => window.__s6.editingModes( id ),
				clientId
			);
			const clicked = await paragraph
				.click( { timeout: 3000 } )
				.then( () => true )
				.catch( () => false );
			if ( ! clicked ) {
				record( `template-part-${ mode }`, {
					rendered,
					modes,
					overlayAfterSelect,
					modesAfterSelect,
					clicked,
				} );
				return;
			}
			await page.keyboard.press( 'End' );
			await page.keyboard.type( ' PART-EDIT' );
			const saves = await saveBoth( page );
			let saveDirty = null;
			if ( lift ) {
				saveDirty = await page.evaluate( async () => {
					window.__s6.clearLog();
					return window.__s6.saveDirty();
				} );
			}
			const server = await rest(
				'GET',
				'wp/v2/template-parts/twentytwentyfive//footer?context=edit&_fields=source,content'
			);
			record( `template-part-${ mode }`, {
				rendered,
				modes,
				modesAfterSelect,
				saves,
				saveDirty,
				server: {
					source: server.source,
					edited: server.content?.raw?.includes( 'PART-EDIT' ),
				},
			} );
		} );

		test( `navigation (${ mode })`, async ( { page } ) => {
			await openEditor( page, { lift } );
			const clientId = await page.evaluate(
				( ref ) =>
					window.__s6.insert( 'core/navigation', {
						ref,
						overlayMenu: 'never',
					} ),
				fixtures.menu
			);
			const nav = page.locator( `[data-block="${ clientId }"]` );
			const link = nav.getByText( 'S6 link' );
			await link.waitFor();
			const modes = await page.evaluate(
				( id ) => window.__s6.editingModes( id ),
				clientId
			);
			await link.click();
			await page.keyboard.press( 'End' );
			await page.keyboard.type( ' NAV-EDIT' );
			const saves = await saveBoth( page );
			let saveDirty = null;
			if ( lift ) {
				saveDirty = await page.evaluate( async () => {
					window.__s6.clearLog();
					return window.__s6.saveDirty();
				} );
			}
			record( `navigation-${ mode }`, { modes, saves, saveDirty } );
		} );

		test( `site title and tagline (${ mode })`, async ( { page } ) => {
			await openEditor( page, { lift } );
			const ids = await page.evaluate( () => [
				window.__s6.insert( 'core/site-title' ),
				window.__s6.insert( 'core/site-tagline' ),
			] );
			const title = page.locator( `[data-block="${ ids[ 0 ] }"]` );
			await title.getByText( 'My WordPress Website' ).waitFor();
			await title.getByText( 'My WordPress Website' ).click();
			await page.keyboard.press( 'End' );
			await page.keyboard.type( ' S6' );
			const tagline = page.locator(
				`[data-block="${ ids[ 1 ] }"] [contenteditable]`
			);
			const taglineEditable = await tagline.count();
			if ( taglineEditable ) {
				await tagline.click();
				await page.keyboard.type( 'S6 tagline' );
			}
			const saves = await saveBoth( page );
			let saveDirty = null;
			if ( lift ) {
				saveDirty = await page.evaluate( async () => {
					window.__s6.clearLog();
					return window.__s6.saveDirty();
				} );
			}
			const server = await rest(
				'GET',
				'wp/v2/settings?_fields=title,description'
			);
			record( `site-${ mode }`, {
				taglineEditable,
				saves,
				saveDirty,
				server,
			} );
			// Restore for the next run.
			await rest( 'POST', 'wp/v2/settings', fixtures.settings );
		} );
	}

	test( 'pattern overrides with bindings sources registered', async ( {
		page,
	} ) => {
		await openEditor( page, { lift: true } );
		const warnings = [];
		page.on( 'console', ( message ) => {
			if ( /bindings/i.test( message.text() ) ) {
				warnings.push( message.text() );
			}
		} );
		const sources = await page.evaluate( () =>
			window.__s6.registerBindings()
		);
		const clientId = await page.evaluate(
			( ref ) => window.__s6.insert( 'core/block', { ref } ),
			fixtures.overrides
		);
		const inner = page
			.locator( `[data-block="${ clientId }"]` )
			.getByText( 'Override me' );
		await inner.waitFor();
		await inner.click();
		await page.keyboard.press( 'End' );
		await page.keyboard.type( ' OVERRIDDEN' );
		const content = await page.evaluate(
			() => window.editor.getTitleAndContent().content
		);
		record( 'overrides-registered', { sources, warnings, content } );
		expect( content ).toContain( 'OVERRIDDEN' );
	} );

	test( 'existing pattern override, as GBK loads it', async ( { page } ) => {
		const markup = `<!-- wp:block {"ref":${ fixtures.overrides },"content":{"Body":{"content":"Server override"}}} /-->`;
		await openEditor( page, { lift: false, content: markup } );
		const block = page.locator( '[data-type="core/block"]' );
		await block.getByText( /Override me|Server override/ ).waitFor();
		const shown = await block.innerText();
		const content = await page.evaluate(
			() => window.editor.getTitleAndContent().content
		);
		record( 'overrides-existing', { shown, content } );
	} );

	test( 'block menu actions that write patterns', async ( { page } ) => {
		await openEditor( page, { lift: false } );
		const menuItems = async ( clientId ) => {
			await page.evaluate(
				( id ) =>
					window.wp.data
						.dispatch( 'core/block-editor' )
						.selectBlock( id ),
				clientId
			);
			await page
				.locator( '.block-editor-block-toolbar' )
				.getByRole( 'button', { name: 'Options' } )
				.click();
			const items = await page.getByRole( 'menuitem' ).allInnerTexts();
			await page.keyboard.press( 'Escape' );
			return items.map( ( text ) => text.split( '\n' )[ 0 ] );
		};
		const paragraph = await page.evaluate( () =>
			window.__s6.insert( 'core/paragraph', { content: 'S6 source' } )
		);
		const firstParagraphItems = await menuItems( paragraph );
		const pattern = await page.evaluate(
			( ref ) => window.__s6.insert( 'core/block', { ref } ),
			fixtures.synced
		);
		await page
			.locator( `[data-block="${ pattern }"]` )
			.getByText( 'Synced original' )
			.waitFor();
		const patternItems = await menuItems( pattern );
		// The create permission resolves after the first menu opens.
		const paragraphItems = await menuItems( paragraph );

		record( 'block-menu', {
			firstParagraphItems,
			paragraphItems,
			patternItems,
		} );
		if ( ! paragraphItems.includes( 'Create pattern' ) ) {
			return;
		}

		// Create a synced pattern from the paragraph, as a user would.
		await page.evaluate(
			( id ) =>
				window.wp.data
					.dispatch( 'core/block-editor' )
					.selectBlock( id ),
			paragraph
		);
		const createItem = page.getByRole( 'menuitem', {
			name: 'Create pattern',
		} );
		const options = page
			.locator( '.block-editor-block-toolbar' )
			.getByRole( 'button', { name: 'Options' } );
		await options.click();
		if ( ! ( await createItem.isVisible() ) ) {
			await options.click();
		}
		await createItem.click();
		await page.getByLabel( 'Name' ).fill( 'S6 created' );
		await page.getByRole( 'button', { name: 'Add' } ).click();
		await page.waitForTimeout( 2000 );
		const created = await page.evaluate( () => ( {
			requests: window.__s6.requests,
			blocks: window.wp.data
				.select( 'core/block-editor' )
				.getBlocks()
				.map( ( b ) => [ b.name, b.attributes.ref ] ),
			notices: window.__s6.notices(),
		} ) );
		record( 'block-menu', {
			firstParagraphItems,
			paragraphItems,
			patternItems,
			created,
		} );
	} );

	test( 'site settings save', async ( { page } ) => {
		await openEditor( page, { lift: true } );
		const id = await page.evaluate( () =>
			window.__s6.insert( 'core/site-title' )
		);
		const title = page
			.locator( `[data-block="${ id }"]` )
			.getByText( 'My WordPress Website' );
		await title.waitFor();
		await title.click();
		await page.keyboard.press( 'End' );
		await page.keyboard.type( ' S6' );
		const saveSite = await page.evaluate( async () => {
			window.__s6.clearLog();
			const result = await window.__s6.saveSite();
			return { ...result, requests: window.__s6.requests };
		} );
		const server = await rest(
			'GET',
			'wp/v2/settings?_fields=title,description'
		);
		record( 'site-save', { saveSite, server } );
		await rest( 'POST', 'wp/v2/settings', fixtures.settings );
	} );
} );
