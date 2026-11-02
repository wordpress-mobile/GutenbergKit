/**
 * SPIKE S1 (CMM-2556): save an existing post through core's `savePost()`.
 *
 * Throwaway: records what happens rather than asserting a final design.
 */
import { test, expect } from '@playwright/test';
import EditorPage from './editor-page';
import { credentials } from './wp-env-fixtures';

let serverPost;

/**
 * Sends an authenticated REST request to wp-env.
 *
 * @param {string} path   REST path, e.g. `wp/v2/posts`.
 * @param {Object} [init] Fetch options.
 * @return {Promise<Object>} The parsed body.
 */
async function rest( path, init = {} ) {
	const response = await fetch( `${ credentials.siteApiRoot }${ path }`, {
		...init,
		headers: {
			Authorization: credentials.authHeader,
			'Content-Type': 'application/json',
			...init.headers,
		},
	} );
	const body = await response.json();
	if ( ! response.ok ) {
		throw new Error( `${ response.status } ${ JSON.stringify( body ) }` );
	}
	return body;
}

/**
 * Loads the editor for `serverPost` the way the hosts do: seeded from the host
 * with the server record preloaded.
 *
 * @param {import('@playwright/test').Page} page Playwright page.
 * @return {Promise<{ events: Array }>} Network log for the post's paths.
 */
async function openEditor( page, hostPost = {} ) {
	const postPaths = new RegExp(
		`/wp/v2/posts/${ serverPost.id }(?:[/?&]|$)`
	);
	const events = [];

	page.on( 'request', ( request ) => {
		if ( ! postPaths.test( decodeURIComponent( request.url() ) ) ) {
			return;
		}
		events.push( {
			kind: 'request',
			method: request.method(),
			url: request.url().replace( credentials.siteApiRoot, '/' ),
			override: request.headers()[ 'x-http-method-override' ],
			body: request.postData(),
		} );
	} );
	page.on( 'response', ( response ) => {
		if ( ! postPaths.test( decodeURIComponent( response.url() ) ) ) {
			return;
		}
		events.push( {
			kind: 'response',
			method: response.request().method(),
			status: response.status(),
		} );
	} );

	await page.addInitScript( () => {
		window.spike = { contentChanged: 0, log: [] };
		window.editorDelegate = {
			onEditorContentChanged: () => window.spike.contentChanged++,
		};
	} );

	const editor = new EditorPage( page );
	await editor.setup( {
		post: {
			id: serverPost.id,
			type: 'post',
			status: serverPost.status,
			title: serverPost.title.raw,
			content: serverPost.content.raw,
			...hostPost,
		},
		preloadData: {
			[ `/wp/v2/posts/${ serverPost.id }?context=edit` ]: {
				body: serverPost,
				headers: {},
			},
		},
	} );

	// Logs api-fetch traffic in page order, interleaved with the save hooks.
	await page.evaluate( () => {
		window.wp.apiFetch.use( ( options, next ) => {
			const method = ( options.method ?? 'GET' ).toUpperCase();
			if ( method === 'GET' ) {
				return next( options );
			}
			window.spike.log.push(
				`fetch:start ${ method } ${ options.path }`
			);
			return next( options ).then(
				( result ) => {
					window.spike.log.push( `fetch:ok ${ method }` );
					return result;
				},
				( err ) => {
					window.spike.log.push( `fetch:error ${ method }` );
					throw err;
				}
			);
		} );
	} );

	return { events };
}

/**
 * Reads the editor's save state.
 *
 * @param {import('@playwright/test').Page} page Playwright page.
 * @return {Promise<Object>} Save state.
 */
function saveState( page ) {
	return page.evaluate( () => {
		const { select } = window.wp.data;
		const editor = select( 'core/editor' );
		const post = editor.getCurrentPost();
		return {
			dirty: editor.isEditedPostDirty(),
			saving: editor.isSavingPost(),
			succeeded: editor.didPostSaveRequestSucceed(),
			failed: editor.didPostSaveRequestFail(),
			modified: post.modified_gmt,
			contentChanged: window.spike.contentChanged,
			log: window.spike.log,
			notices: select( 'core/notices' )
				.getNotices()
				.map( ( { id, status, content } ) => ( {
					id,
					status,
					content,
				} ) ),
		};
	} );
}

test.describe( 'SPIKE S1: existing-post save', () => {
	test.beforeEach( async () => {
		serverPost = await rest( 'wp/v2/posts?context=edit', {
			method: 'POST',
			body: JSON.stringify( {
				status: 'draft',
				title: 'Spike title',
				content:
					'<!-- wp:paragraph -->\n<p>Spike content</p>\n<!-- /wp:paragraph -->',
			} ),
		} );
	} );

	test.afterEach( async () => {
		await rest( `wp/v2/posts/${ serverPost.id }?force=true`, {
			method: 'DELETE',
		} );
	} );

	test( 'saves an edited post', async ( { page } ) => {
		const { events } = await openEditor( page );

		await page.getByText( 'Spike content' ).click();
		await page.keyboard.type( ' edited' );
		await expect
			.poll( () => saveState( page ).then( ( s ) => s.dirty ) )
			.toBe( true );

		const before = await saveState( page );
		await page.evaluate( () =>
			window.wp.data.dispatch( 'core/editor' ).savePost()
		);
		const after = await saveState( page );
		const server = await rest(
			`wp/v2/posts/${ serverPost.id }?context=edit`
		);

		console.log(
			'S1 save',
			JSON.stringify(
				{ events, before, after, serverModified: server.modified_gmt },
				null,
				2
			)
		);

		expect( server.content.raw ).toContain( 'Spike content edited' );
		expect( after ).toMatchObject( {
			dirty: false,
			saving: false,
			succeeded: true,
			failed: false,
			modified: server.modified_gmt,
		} );
	} );

	test( 'records hook order when editor.savePost throws', async ( {
		page,
	} ) => {
		await openEditor( page );

		await page.evaluate( () => {
			const { addFilter, addAction } = window.wp.hooks;
			addFilter( 'editor.preSavePost', 'spike', async ( edits ) => {
				window.spike.log.push( 'hook:preSavePost' );
				return edits;
			} );
			addFilter( 'editor.__unstableSavePost', 'spike', ( promise ) =>
				promise.then( () =>
					window.spike.log.push( 'hook:__unstableSavePost' )
				)
			);
			addAction( 'editor.savePost', 'spike', async () => {
				window.spike.log.push( 'hook:savePost (throws)' );
				throw new Error( 'Spike hook failure' );
			} );
		} );

		await page.getByText( 'Spike content' ).click();
		await page.keyboard.type( ' hooked' );

		await page.evaluate( () =>
			window.wp.data.dispatch( 'core/editor' ).savePost()
		);
		const after = await saveState( page );
		const server = await rest(
			`wp/v2/posts/${ serverPost.id }?context=edit`
		);

		console.log(
			'S1 hook throws',
			JSON.stringify(
				{
					after,
					serverHasEdit: server.content.raw.includes( 'hooked' ),
				},
				null,
				2
			)
		);

		expect( after.log ).toEqual( [
			'hook:preSavePost',
			`fetch:start PUT /wp/v2/posts/${ serverPost.id }`,
			'fetch:ok PUT',
			'hook:__unstableSavePost',
			'hook:savePost (throws)',
		] );
	} );

	test( 'records state when editor.preSavePost throws after a good save', async ( {
		page,
	} ) => {
		await openEditor( page );

		await page.getByText( 'Spike content' ).click();
		await page.keyboard.type( ' first' );
		await page.evaluate( () =>
			window.wp.data.dispatch( 'core/editor' ).savePost()
		);

		await page.evaluate( () => {
			window.wp.hooks.addFilter( 'editor.preSavePost', 'spike', () => {
				window.spike.log.push( 'hook:preSavePost (throws)' );
				throw new Error( 'Spike preSave failure' );
			} );
		} );
		await page.keyboard.type( ' second' );
		await page.evaluate( () =>
			window.wp.data.dispatch( 'core/editor' ).savePost()
		);
		const after = await saveState( page );

		console.log( 'S1 preSave throws', JSON.stringify( after, null, 2 ) );
	} );

	test( 'records whether unsynced host edits reach the server', async ( {
		page,
	} ) => {
		const { events } = await openEditor( page, {
			title: 'Host-only title',
			content:
				'<!-- wp:paragraph -->\n<p>Host-only content</p>\n<!-- /wp:paragraph -->',
		} );

		const before = await saveState( page );
		await page.getByText( 'Host-only content' ).click();
		await page.keyboard.type( ' edited' );
		await page.evaluate( () =>
			window.wp.data.dispatch( 'core/editor' ).savePost()
		);
		const after = await saveState( page );
		const server = await rest(
			`wp/v2/posts/${ serverPost.id }?context=edit`
		);

		console.log(
			'S1 unsynced host edits',
			JSON.stringify(
				{
					dirtyOnOpen: before.dirty,
					writes: events.filter(
						( e ) => e.kind === 'request' && e.method !== 'GET'
					),
					dirtyAfter: after.dirty,
					titleShownAfter: await page
						.getByRole( 'textbox', { name: 'Add title' } )
						.textContent(),
					serverTitle: server.title.raw,
					serverContent: server.content.raw,
				},
				null,
				2
			)
		);
	} );

	test( 'saves with the keyboard shortcut', async ( { page } ) => {
		const { events } = await openEditor( page );

		await page.getByText( 'Spike content' ).click();
		await page.keyboard.type( ' shortcut' );
		await page.keyboard.press( 'ControlOrMeta+s' );

		await expect
			.poll( () => saveState( page ).then( ( s ) => s.succeeded ) )
			.toBe( true );
		console.log(
			'S1 shortcut',
			JSON.stringify( events.filter( ( e ) => e.method !== 'GET' ) )
		);
	} );

	test( 'records whether savePost honours the saving lock', async ( {
		page,
	} ) => {
		const { events } = await openEditor( page );

		await page.getByText( 'Spike content' ).click();
		await page.keyboard.type( ' locked' );
		await page.evaluate( () => {
			const { dispatch } = window.wp.data;
			dispatch( 'core/editor' ).lockPostSaving( 'spike' );
			return dispatch( 'core/editor' ).savePost();
		} );
		const after = await saveState( page );

		console.log(
			'S1 locked',
			JSON.stringify( {
				writes: events.filter(
					( e ) => e.kind === 'request' && e.method !== 'GET'
				),
				after,
			} )
		);
	} );
} );
