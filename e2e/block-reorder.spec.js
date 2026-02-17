/**
 * External dependencies
 */
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import EditorPage from './editor-page';

test.describe( 'Block Reorder', () => {
	test( 'should move a block down', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.insertBlock( 'core/paragraph', {
			content: 'First',
		} );
		await editor.insertBlock( 'core/paragraph', {
			content: 'Second',
		} );

		// Select the first block and move it down.
		await editor.selectBlock( 0 );
		await page.getByRole( 'button', { name: 'Move down' } ).click();

		const blocks = await editor.getBlocks();
		expect( blocks[ 0 ].attributes.content ).toBe( 'Second' );
		expect( blocks[ 1 ].attributes.content ).toBe( 'First' );
	} );

	test( 'should move a block up', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.insertBlock( 'core/paragraph', {
			content: 'First',
		} );
		await editor.insertBlock( 'core/paragraph', {
			content: 'Second',
		} );

		// Select the second block and move it up.
		await editor.selectBlock( 1 );
		await page.getByRole( 'button', { name: 'Move up' } ).click();

		const blocks = await editor.getBlocks();
		expect( blocks[ 0 ].attributes.content ).toBe( 'Second' );
		expect( blocks[ 1 ].attributes.content ).toBe( 'First' );
	} );

	test( 'should disable move up on first block', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.insertBlock( 'core/paragraph', {
			content: 'First',
		} );
		await editor.insertBlock( 'core/paragraph', {
			content: 'Second',
		} );

		await editor.selectBlock( 0 );
		await expect(
			page.getByRole( 'button', { name: 'Move up' } )
		).toBeDisabled();
	} );

	test( 'should disable move down on last block', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.insertBlock( 'core/paragraph', {
			content: 'First',
		} );
		await editor.insertBlock( 'core/paragraph', {
			content: 'Second',
		} );

		await editor.selectBlock( 1 );
		await expect(
			page.getByRole( 'button', { name: 'Move down' } )
		).toBeDisabled();
	} );
} );
