/**
 * SPIKE S4 (CMM-2559): inject save failures and record how each is classified.
 *
 * Throwaway: records what happens rather than asserting a final design. Each
 * case writes its record to `build/s4-web/<case>.json`.
 */
import fs from 'node:fs';
import path from 'node:path';
import { test, expect } from '@playwright/test';
import EditorPage from './editor-page';
import { credentials } from './wp-env-fixtures';

const OUT_DIR = path.resolve( import.meta.dirname, '../build/s4-web' );

test.describe.configure( { mode: 'serial' } );

async function rest( restPath, init = {} ) {
	const response = await fetch( `${ credentials.siteApiRoot }${ restPath }`, {
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

function setMode( mode, query = '' ) {
	return rest(
		`gutenbergkit/v1/post-write-failure?mode=${ mode }${ query }`,
		{
			method: 'POST',
		}
	);
}

async function serverState( id ) {
	const post = await rest(
		`wp/v2/posts/${ id }?context=edit&_fields=modified_gmt,content`
	);
	return {
		modifiedGmt: post.modified_gmt,
		content: post.content.raw,
	};
}

async function openEditor( page, title ) {
	const serverPost = await rest( 'wp/v2/posts?context=edit', {
		method: 'POST',
		body: JSON.stringify( {
			title,
			status: 'draft',
			content:
				'<!-- wp:paragraph -->\n<p>S4 baseline.</p>\n<!-- /wp:paragraph -->',
		} ),
	} );
	page.on( 'console', ( message ) => {
		if ( message.type() === 'error' ) {
			// eslint-disable-next-line no-console
			console.log( `[page error] ${ message.text() }` );
		}
	} );
	page.on( 'pageerror', ( err ) =>
		// eslint-disable-next-line no-console
		console.log( `[pageerror] ${ err.stack }` )
	);
	const editor = new EditorPage( page );
	await editor.setup( {
		post: {
			id: serverPost.id,
			type: 'post',
			status: serverPost.status,
			title: serverPost.title.raw,
			content: serverPost.content.raw,
		},
		preloadData: {
			[ `/wp/v2/posts/${ serverPost.id }?context=edit` ]: {
				body: serverPost,
				headers: {},
			},
		},
	} );
	await page.waitForFunction( () => window.__s4 );
	return serverPost;
}

async function editAndSave( page, { beforeSave } = {} ) {
	await page.evaluate( () => window.__s4.edit() );
	if ( beforeSave ) {
		await beforeSave();
	}
	return page.evaluate( () => window.__s4.save() );
}

async function record( page, name, serverPost, outcome, extra = {} ) {
	const server = await serverState( serverPost.id );
	const pending = await page.evaluate( () => window.__s4.journalRead() );
	const snapshotHash = pending?.snapshotHash;
	const reconcileResult = pending
		? await page.evaluate( () => window.__s4.reconcile() )
		: null;
	const log = await page.evaluate( () =>
		window.__s4.log.map(
			( { t, message, data } ) =>
				`${ t } ${ message } ${ JSON.stringify( data ?? {} ) }`
		)
	);
	const result = {
		name,
		postId: serverPost.id,
		outcome,
		server: {
			modifiedGmt: server.modifiedGmt,
			hasEdit: /S4 edit at/.test( server.content ),
			hasConcurrentEdit: /Concurrent edit/.test( server.content ),
			hash: await page.evaluate(
				( content ) => window.__s4.hash( content ),
				server.content
			),
		},
		pendingAfter: pending,
		snapshotHash,
		reconcile: reconcileResult,
		...extra,
		log,
	};
	fs.mkdirSync( OUT_DIR, { recursive: true } );
	fs.writeFileSync(
		path.join( OUT_DIR, `${ name }.json` ),
		JSON.stringify( result, null, 2 )
	);
	return result;
}

test.afterEach( async () => {
	await setMode( 'off' );
} );

test( 'baseline: off', async ( { page } ) => {
	await setMode( 'off' );
	const post = await openEditor( page, 'S4 web baseline' );
	const outcome = await editAndSave( page );
	const result = await record( page, 'off', post, outcome );
	expect( result.outcome.outcome ).toBe( 'saved' );
} );

test( 'error500', async ( { page } ) => {
	const post = await openEditor( page, 'S4 web error500' );
	await setMode( 'error500' );
	const outcome = await editAndSave( page );
	const result = await record( page, 'error500', post, outcome );
	expect( result.outcome.outcome ).toBe( 'failed' );
} );

test( 'drop', async ( { page } ) => {
	const post = await openEditor( page, 'S4 web drop' );
	await setMode( 'drop' );
	const outcome = await editAndSave( page );
	const result = await record( page, 'drop', post, outcome );
	expect( result.outcome.outcome ).toBe( 'failed' );
} );

test( 'slow90s', async ( { page } ) => {
	test.setTimeout( 180_000 );
	const post = await openEditor( page, 'S4 web slow90s' );
	await setMode( 'slow90s' );
	const started = Date.now();
	const outcome = await editAndSave( page );
	const result = await record( page, 'slow90s', post, outcome, {
		elapsedMs: Date.now() - started,
	} );
	expect( result.outcome.outcome ).toBeDefined();
} );

test( 'conflict: content edited elsewhere', async ( { page } ) => {
	const post = await openEditor( page, 'S4 web conflict' );
	// Probes whether GBK's persisted-post overlay hides the other writer's
	// content when the response carries the post's ID.
	const outcome = await editAndSave( page, {
		beforeSave: () => setMode( 'conflict', `&post=${ post.id }` ),
	} );
	const overlay = await page.evaluate( async ( id ) => {
		const { apiFetch } = window.wp;
		const withId = await apiFetch( {
			path: `/wp/v2/posts/${ id }?context=edit&_fields=id,modified_gmt,content`,
		} );
		const withoutId = await apiFetch( {
			path: `/wp/v2/posts/${ id }?context=edit&_fields=modified_gmt,content`,
		} );
		return {
			withIdHasConcurrentEdit: /Concurrent edit/.test(
				withId.content.raw
			),
			withoutIdHasConcurrentEdit: /Concurrent edit/.test(
				withoutId.content.raw
			),
		};
	}, post.id );
	const result = await record( page, 'conflict', post, outcome, {
		overlay,
	} );
	expect( result.outcome.outcome ).toBe( 'aborted' );
} );

test( 'conflict: only modified bumped', async ( { page } ) => {
	const post = await openEditor( page, 'S4 web conflict-mod' );
	const outcome = await editAndSave( page, {
		beforeSave: () =>
			setMode( 'conflict', `&post=${ post.id }&content=false` ),
	} );
	const result = await record(
		page,
		'conflict-modified-only',
		post,
		outcome
	);
	expect( result.outcome.outcome ).toBe( 'saved' );
} );

test( 'hook error after the write', async ( { page } ) => {
	await setMode( 'off' );
	const post = await openEditor( page, 'S4 web hook error' );
	await page.evaluate( () => {
		window.wp.hooks.addAction( 'editor.savePost', 's4/throws', () => {
			throw new Error( 'S4 plugin hook failure' );
		} );
	} );
	const outcome = await editAndSave( page );
	const result = await record( page, 'hook-error', post, outcome );
	expect( result.outcome.outcome ).toBe( 'saved' );
} );

test( 'render error while the PUT is in flight', async ( { page } ) => {
	await setMode( 'off' );
	const post = await openEditor( page, 'S4 web crash' );
	const bridge = [];
	await page.exposeFunction( 's4Bridge', ( message ) =>
		bridge.push( message )
	);
	await page.evaluate( () => {
		window.editorDelegate = {
			...( window.editorDelegate ?? {} ),
			onEditorUnavailable: ( ...args ) =>
				window.s4Bridge(
					`onEditorUnavailable ${ JSON.stringify( args ) }`
				),
		};
	} );
	await page.evaluate( () => window.__s4.edit() );
	const outcome = await page.evaluate( async () => {
		const pending = window.__s4.save();
		// Arm the crash as soon as the logger sees the write go out.
		await new Promise( ( resolve ) => {
			const check = () => {
				if (
					window.__s4.log.some( ( e ) => /→ PUT/.test( e.message ) )
				) {
					window.__s4.crash();
					resolve();
				} else {
					setTimeout( check, 5 );
				}
			};
			check();
		} );
		return pending;
	} );
	const afterCrash = await page.evaluate( () => ( {
		boundaryShown: !! document.querySelector( '.editor-error-boundary' ),
		bridgeMethods: Object.keys( window.editor ?? {} ),
		editorPostId: window.wp.data.select( 'core/editor' ).getCurrentPostId(),
		editedContent: window.wp.data
			.select( 'core/editor' )
			.getEditedPostContent(),
	} ) );
	const result = await record( page, 'crash', post, outcome, {
		afterCrash,
		bridge,
	} );
	expect( result.outcome.outcome ).toBeDefined();
} );
