/**
 * SPIKE S3 (CMM-2558): adopt a server post ID in place of the unsaved `-1`.
 *
 * Throwaway: records what happens rather than asserting a final design.
 */
import { test } from '@playwright/test';
import EditorPage from './editor-page';

const NEW_POST = {
	id: -1,
	type: 'post',
	restBase: 'posts',
	restNamespace: 'wp/v2',
	status: 'draft',
	title: '',
	content: '',
};

/**
 * Opens a new post with a host bridge stub that counts events.
 *
 * @param {import('@playwright/test').Page} page      Playwright page.
 * @param {Object}                          [hostPost] Overrides for the post.
 * @return {Promise<EditorPage>} The editor.
 */
async function openNewPost( page, hostPost = {} ) {
	await page.addInitScript( () => {
		window.hostEvents = [];
		// Every bridge method is a no-op, and the ones S3 measures are recorded.
		window.editorDelegate = new Proxy(
			{},
			{
				get: ( target, name ) => ( payload ) => {
					if ( name === 'onEditorContentChanged' ) {
						window.hostEvents.push(
							`contentChanged @${ Math.round(
								performance.now()
							) }`
						);
					} else if ( name === 'onEditorHistoryChanged' ) {
						window.hostEvents.push( `history ${ payload }` );
					}
					return undefined;
				},
				has: () => true,
			}
		);
	} );
	page.on( 'console', ( message ) => {
		if ( message.text().startsWith( '[spike]' ) ) {
			// eslint-disable-next-line no-console
			console.log( message.text() );
		}
	} );

	const editor = new EditorPage( page );
	await editor.setup( { post: { ...NEW_POST, ...hostPost } } );
	return editor;
}

function state( page ) {
	return page.evaluate( () => {
		const editor = window.wp.data.select( 'core/editor' );
		const active = document.activeElement;
		return {
			postId: editor.getCurrentPostId(),
			title: editor.getEditedPostAttribute( 'title' ),
			content: editor.getEditedPostContent(),
			isDirty: editor.isEditedPostDirty(),
			isNew: editor.isEditedPostNew(),
			isAutosaveable: editor.isEditedPostAutosaveable(),
			now: Math.round( performance.now() ),
			hasUndo: editor.hasEditorUndo(),
			hasRedo: editor.hasEditorRedo(),
			active: active?.closest( '[data-block]' )?.dataset.block
				? 'block'
				: active?.className,
			hostEvents: [ ...window.hostEvents ],
			counters: {
				renders: window.__spike.blockEditRenders,
				mounts: window.__spike.blockEditMounts,
				unmounts: window.__spike.blockEditUnmounts,
				domAdded: window.__spike.domBlocksAdded,
				domRemoved: window.__spike.domBlocksRemoved,
			},
		};
	} );
}

function report( label, value ) {
	// eslint-disable-next-line no-console
	console.log(
		`\n=== ${ label } ===\n${ JSON.stringify( value, null, 2 ) }`
	);
}

test.describe( 'SPIKE S3: in-place post ID adoption', () => {
	test( 'adopts while typing in a paragraph', async ( { page } ) => {
		const editor = await openNewPost( page );

		await page.getByRole( 'textbox', { name: 'Add title' } ).click();
		await page.keyboard.type( 'Adopted title' );
		await page.keyboard.press( 'Enter' );
		await page.keyboard.type( 'First words' );
		// Let the AutosaveMonitor (1s) report the typing first.
		await page.waitForTimeout( 1500 );

		report( 'before', await state( page ) );
		const result = await page.evaluate( () =>
			window.editor.spikeCreateAndAdopt()
		);
		report( 'adoption', result );

		// Keep typing without refocusing: does the caret survive?
		await page.keyboard.type( ' and more' );
		await page.waitForTimeout( 1500 );
		report( 'after typing', await state( page ) );
		report( 'blocks', await editor.getBlocks() );

		// Undo: does it step back the visible post, or the `-1` record?
		await page.evaluate( () => window.editor.undo() );
		await page.waitForTimeout( 300 );
		report( 'after 1 undo', await state( page ) );
		for ( let i = 0; i < 20; i++ ) {
			await page.evaluate( () => window.editor.undo() );
		}
		await page.waitForTimeout( 300 );
		report( 'after 21 undos', await state( page ) );
	} );

	test( 'adopts while the title is focused', async ( { page } ) => {
		await openNewPost( page );

		await page.getByRole( 'textbox', { name: 'Add title' } ).click();
		await page.keyboard.type( 'Title only' );
		await page.waitForTimeout( 1500 );

		const result = await page.evaluate( () =>
			window.editor.spikeCreateAndAdopt()
		);
		report( 'title adoption', result );

		await page.keyboard.type( ' continued' );
		await page.waitForTimeout( 1500 );
		report( 'title after typing', await state( page ) );
	} );

	test( 'adopts a local draft with blocks and no edits', async ( {
		page,
	} ) => {
		await openNewPost( page, {
			title: 'Local draft',
			content:
				'<!-- wp:paragraph -->\n<p>One</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:paragraph -->\n<p>Two</p>\n<!-- /wp:paragraph -->',
		} );
		report( 'local draft before', await state( page ) );

		const result = await page.evaluate( () =>
			window.editor.spikeCreateAndAdopt()
		);
		report( 'local draft adoption', result );
		await page.waitForTimeout( 1500 );
		report( 'local draft after', await state( page ) );
	} );

	for ( const noBlocksCopy of [ true, false ] ) {
		test( `adopts a local draft with the caret in a block (blocks copy: ${ ! noBlocksCopy })`, async ( {
			page,
		} ) => {
			await page.addInitScript( ( value ) => {
				window.__spikeNoBlocksCopy = value;
			}, noBlocksCopy );
			await openNewPost( page, {
				title: 'Local draft',
				content:
					'<!-- wp:paragraph -->\n<p>One</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:paragraph -->\n<p>Two</p>\n<!-- /wp:paragraph -->',
			} );
			const autosaveRequests = [];
			page.on( 'requestfinished', async ( request ) => {
				if ( request.url().includes( '/autosaves' ) ) {
					const response = await request.response();
					autosaveRequests.push(
						`${ decodeURIComponent( request.url() ).replace(
							/^.*\/wp-json/,
							''
						) } ${ response?.status() }`
					);
				}
			} );
			await page.getByText( 'Two' ).click();
			await page.keyboard.press( 'End' );

			const result = await page.evaluate( () =>
				window.editor.spikeCreateAndAdopt()
			);
			report( `caret draft adoption (copy ${ ! noBlocksCopy })`, {
				copiedEditKeys: result.copiedEditKeys,
				same: result.same,
				delta: result.delta,
				focusBefore: result.before.activeElement,
				focusAfter: result.after.activeElement,
				domSelectionAfter: result.after.domSelection,
				dirtyAfter: result.after.isDirty,
			} );

			await page.keyboard.type( ' typed' );
			await page.waitForTimeout( 5000 );
			const after = await state( page );
			report( `caret draft after typing (copy ${ ! noBlocksCopy })`, {
				content: after.content,
				hostEvents: after.hostEvents,
				isDirty: after.isDirty,
				isAutosaveable: after.isAutosaveable,
				now: after.now,
				autosaveRequests,
			} );
		} );
	}

	test( 'saves to the adopted ID afterwards', async ( { page } ) => {
		await openNewPost( page );
		await page.getByRole( 'textbox', { name: 'Add title' } ).click();
		await page.keyboard.type( 'Save after adopt' );
		await page.keyboard.press( 'Enter' );
		await page.keyboard.type( 'Body' );
		await page.waitForTimeout( 1500 );

		const requests = [];
		page.on( 'request', ( request ) => {
			if ( request.url().includes( '/wp/v2/posts' ) ) {
				requests.push(
					`${ request.method() } ${ decodeURIComponent(
						request.url()
					).replace( /^.*\/wp-json/, '' ) }`
				);
			}
		} );

		const { to } = await page.evaluate( () =>
			window.editor.spikeCreateAndAdopt()
		);
		await page.keyboard.type( ' edited' );
		await page.waitForTimeout( 500 );
		await page.evaluate( () =>
			window.wp.data.dispatch( 'core/editor' ).savePost()
		);
		await page.waitForTimeout( 1500 );

		const server = await page.evaluate(
			( id ) =>
				window.wp.apiFetch( {
					path: `/wp/v2/posts/${ id }?context=edit`,
				} ),
			to
		);
		report( 'save after adopt', {
			requests,
			state: await state( page ),
			server: {
				title: server.title.raw,
				content: server.content.raw,
				status: server.status,
			},
		} );
	} );
} );
