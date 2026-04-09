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
 * Intercept the posts REST endpoint so we can observe requests without hitting
 * the real server.  The mock returns a realistic post object with a
 * server-assigned ID so the editor can update its internal state.
 *
 * @param {import('@playwright/test').Page} page       Playwright page.
 * @param {Object}                          options
 * @param {number}                          options.id The ID the "server" assigns to a newly created post.
 * @return {Promise<Array>} A reference to the captured requests array.
 */
async function mockPostsEndpoint( page, { id } ) {
	const requests = [];
	const apiBase = credentials.siteApiRoot;

	await page.route( `${ apiBase }wp/v2/posts**`, ( route ) => {
		const method = route.request().method();
		const url = route.request().url();
		requests.push( { method, url } );

		const body = {
			id,
			type: 'post',
			status: 'draft',
			title: { raw: '', rendered: '' },
			content: { raw: '', rendered: '' },
		};

		return route.fulfill( {
			status: 200,
			contentType: 'application/json',
			body: JSON.stringify( body ),
		} );
	} );

	return requests;
}

test.describe( 'Save Post', () => {
	test( 'first save creates (POST), subsequent save updates (PUT)', async ( {
		page,
	} ) => {
		const SERVER_ID = 999;
		const requests = await mockPostsEndpoint( page, { id: SERVER_ID } );

		const editor = new EditorPage( page );
		await editor.setup( {
			post: { id: -1, status: 'draft', title: '', content: '' },
		} );

		// Type something so the editor considers the post saveable.
		await editor.clickBlockAppender();
		await page.keyboard.type( 'Hello' );

		// --- First save: should POST (create) ---
		await page.evaluate( () => window.editor.savePost() );

		const createRequest = requests.find( ( r ) => r.method === 'POST' );
		expect( createRequest ).toBeDefined();

		// The server-assigned ID is recorded as an edit on the existing
		// entity (not via setEditedPost) so the title contentEditable
		// is preserved.  Verify the edited entity reflects the new ID.
		const editedId = await page.evaluate( () => {
			const postId = window.wp.data
				.select( 'core/editor' )
				.getCurrentPostId();
			return window.wp.data
				.select( 'core' )
				.getEditedEntityRecord( 'postType', 'post', postId )?.id;
		} );
		expect( editedId ).toBe( SERVER_ID );

		// --- Second save: should PUT (update) to the created ID ---
		// Make an edit so the editor considers the post saveable again.
		await page.keyboard.type( ' World' );
		requests.length = 0;
		await page.evaluate( () => window.editor.savePost() );

		const updateRequest = requests.find( ( r ) => r.method === 'PUT' );
		expect( updateRequest ).toBeDefined();
		expect( updateRequest.url ).toContain( `/posts/${ SERVER_ID }` );

		// No additional POST (create) should have been sent.
		const extraCreates = requests.filter( ( r ) => r.method === 'POST' );
		expect( extraCreates ).toHaveLength( 0 );
	} );
} );
