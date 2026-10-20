import { test, expect } from '@playwright/test';
import EditorPage from './editor-page';
import { credentials } from './wp-env-fixtures';
import { fetchJson } from './fetch-json';

/** Matches the post's own path, not sub-resources like its autosaves. */
const POST_PATH = /\/wp\/v2\/posts\/1(?:[?&]|$)/;

/** Matches the post's path and its sub-resources. */
const POST_PATHS = /\/wp\/v2\/posts\/1(?:[/?&]|$)/;

const HOST_POST = {
	id: 1,
	type: 'post',
	status: 'draft',
	title: 'Host title',
	content:
		'<!-- wp:paragraph -->\n<p>Host content</p>\n<!-- /wp:paragraph -->',
};

test.describe( 'Post entity seeding', () => {
	let serverPost;

	test.beforeAll( async () => {
		serverPost = await fetchJson(
			`${ credentials.siteApiRoot }wp/v2/posts/1?context=edit`,
			credentials,
			'post'
		);
	} );

	test( 'seeds the preloaded post without requesting it', async ( {
		page,
	} ) => {
		const postRequests = [];
		page.on( 'request', ( request ) => {
			if ( POST_PATH.test( decodeURIComponent( request.url() ) ) ) {
				postRequests.push( `${ request.method() } ${ request.url() }` );
			}
		} );

		// Stand in for the Android bridge, which receives host events on
		// `window.editorDelegate`.
		await page.addInitScript( () => {
			window.contentChangedCount = 0;
			window.featuredImageChanges = [];
			window.editorDelegate = {
				onEditorContentChanged: () => window.contentChangedCount++,
				onEditorFeaturedImageChanged: ( mediaID ) =>
					window.featuredImageChanges.push( mediaID ),
			};
		} );

		const editor = new EditorPage( page );
		await editor.setup( {
			post: HOST_POST,
			preloadData: {
				'/wp/v2/posts/1?context=edit': {
					// The host may hold a different, unsynced featured image.
					body: { ...serverPost, featured_media: 123 },
					headers: {},
				},
			},
		} );

		await expect(
			page.getByRole( 'textbox', { name: 'Add title' } )
		).toHaveText( 'Host title' );
		await expect( page.getByText( 'Host content' ) ).toBeVisible();

		const record = await page.evaluate( () =>
			window.wp.data
				.select( 'core' )
				.getEntityRecord( 'postType', 'post', 1 )
		);
		expect( record.date ).toBe( serverPost.date );
		expect( record.author ).toBe( serverPost.author );
		expect( record.title.raw ).toBe( 'Host title' );

		expect(
			await page.evaluate( () =>
				window.wp.data.select( 'core/editor' ).isEditedPostDirty()
			)
		).toBe( false );
		expect( await page.evaluate( () => window.contentChangedCount ) ).toBe(
			0
		);
		expect(
			await page.evaluate( () => window.featuredImageChanges )
		).toEqual( [] );
		expect( postRequests ).toEqual( [] );

		await page.getByText( 'Host content' ).click();
		await page.keyboard.type( ' edited' );

		await expect
			.poll( () => page.evaluate( () => window.contentChangedCount ) )
			.toBeGreaterThan( 0 );
	} );

	test( "uses core's post type entity configurations", async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup( { post: HOST_POST } );

		const config = await page.evaluate( () => {
			const configs = window.wp.data
				.select( 'core' )
				.getEntitiesConfig( 'postType' )
				.filter( ( { name } ) =>
					[ 'post', 'attachment', 'wp_block' ].includes( name )
				);
			return configs.map( ( entity ) => ( {
				name: entity.name,
				baseURL: entity.baseURL,
				baseURLParams: entity.baseURLParams,
				prePersist: typeof entity.__unstablePrePersist,
			} ) );
		} );

		expect( config ).toEqual(
			[
				[ 'post', '/wp/v2/posts' ],
				[ 'attachment', '/wp/v2/media' ],
				[ 'wp_block', '/wp/v2/blocks' ],
			].map( ( [ name, baseURL ] ) => ( {
				name,
				baseURL,
				baseURLParams: { context: 'edit' },
				prePersist: 'function',
			} ) )
		);
	} );

	test( 'renders the post when the post types fail to load', async ( {
		page,
	} ) => {
		await page.route( /\/wp\/v2\/types\?/, ( route ) => route.abort() );

		const editor = new EditorPage( page );
		await editor.setup( { post: HOST_POST, preloadData: {} } );

		await expect(
			page.getByRole( 'textbox', { name: 'Add title' } )
		).toHaveText( 'Host title' );
		await expect( page.getByText( 'Host content' ) ).toBeVisible();
	} );

	test( "keeps the host's title and content when the post is fetched", async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup( { post: HOST_POST } );

		const records = await page.evaluate( async () => {
			const { resolveSelect, select } = window.wp.data;
			const { getEntityRecord, getEntityRecords } =
				resolveSelect( 'core' );
			await getEntityRecord( 'postType', 'post', 1, { _embed: true } );
			await getEntityRecords( 'postType', 'post', { include: [ 1 ] } );
			return {
				embedded: select( 'core' ).getEntityRecord(
					'postType',
					'post',
					1,
					{ _embed: true }
				),
				listed: select( 'core' ).getEntityRecords( 'postType', 'post', {
					include: [ 1 ],
				} )[ 0 ],
				edited: select( 'core/editor' ).getEditedPostAttribute(
					'title'
				),
				dirty: select( 'core/editor' ).isEditedPostDirty(),
			};
		} );

		for ( const record of [ records.embedded, records.listed ] ) {
			expect( record.title.raw ).toBe( 'Host title' );
			expect( record.content.raw ).toBe( HOST_POST.content );
			expect( record.title.rendered ).toBe( serverPost.title.rendered );
		}
		expect( records.embedded._embedded ).toBeDefined();
		expect( records.edited ).toBe( 'Host title' );
		expect( records.dirty ).toBe( false );
		await expect(
			page.getByRole( 'textbox', { name: 'Add title' } )
		).toHaveText( 'Host title' );
	} );

	test( 'blocks saving the post from the editor', async ( { page } ) => {
		const writeRequests = [];
		page.on( 'request', ( request ) => {
			if (
				request.method() !== 'GET' &&
				request.method() !== 'OPTIONS' &&
				POST_PATHS.test( decodeURIComponent( request.url() ) )
			) {
				writeRequests.push( request.url() );
			}
		} );

		const editor = new EditorPage( page );
		await editor.setup( { post: HOST_POST } );

		await page.getByText( 'Host content' ).click();
		await page.keyboard.type( ' edited' );

		const result = await page.evaluate( async () => {
			const { dispatch, select } = window.wp.data;
			await dispatch( 'core/editor' ).savePost();
			return {
				failed: select( 'core/editor' ).didPostSaveRequestFail(),
				dirty: select( 'core/editor' ).isEditedPostDirty(),
			};
		} );

		expect( result ).toEqual( { failed: true, dirty: true } );
		expect( writeRequests ).toEqual( [] );
	} );
} );
