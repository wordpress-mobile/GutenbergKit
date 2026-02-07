/**
 * External dependencies
 */
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import { setupEditor, getBlocks } from './editor-setup';

test.describe( 'Split and Merge Blocks', () => {
	test( 'should split a paragraph block with Enter', async ( { page } ) => {
		await setupEditor( page );

		await page
			.locator( 'button.gutenberg-kit-default-block-appender' )
			.click();
		await page.keyboard.type( 'FirstSecond' );

		// Move caret between "First" and "Second".
		for ( let i = 0; i < 6; i++ ) {
			await page.keyboard.press( 'ArrowLeft' );
		}

		await page.keyboard.press( 'Enter' );

		const blocks = await getBlocks( page );
		expect( blocks ).toHaveLength( 2 );
		expect( blocks[ 0 ].attributes.content ).toBe( 'First' );
		expect( blocks[ 1 ].attributes.content ).toBe( 'Second' );
	} );

	test( 'should merge two paragraph blocks with Backspace', async ( {
		page,
	} ) => {
		await setupEditor( page );

		// Create two blocks by typing and splitting.
		await page
			.locator( 'button.gutenberg-kit-default-block-appender' )
			.click();
		await page.keyboard.type( 'FirstSecond' );
		for ( let i = 0; i < 6; i++ ) {
			await page.keyboard.press( 'ArrowLeft' );
		}
		await page.keyboard.press( 'Enter' );

		// Cursor is now at the start of the second block. Press Backspace to merge.
		await page.keyboard.press( 'Home' );
		await page.keyboard.press( 'Backspace' );

		const blocks = await getBlocks( page );
		expect( blocks ).toHaveLength( 1 );
		expect( blocks[ 0 ].attributes.content ).toBe( 'FirstSecond' );
	} );

	test( 'should preserve content after split and merge roundtrip', async ( {
		page,
	} ) => {
		await setupEditor( page );

		const originalText = 'The quick brown fox';

		await page
			.locator( 'button.gutenberg-kit-default-block-appender' )
			.click();
		await page.keyboard.type( originalText );

		// Split in the middle ("The quick" | " brown fox").
		for ( let i = 0; i < 10; i++ ) {
			await page.keyboard.press( 'ArrowLeft' );
		}
		await page.keyboard.press( 'Enter' );

		let blocks = await getBlocks( page );
		expect( blocks ).toHaveLength( 2 );

		// Merge back.
		await page.keyboard.press( 'Home' );
		await page.keyboard.press( 'Backspace' );

		blocks = await getBlocks( page );
		expect( blocks ).toHaveLength( 1 );
		expect( blocks[ 0 ].attributes.content ).toBe( originalText );
	} );

	test( 'should split and merge preserving inline formatting', async ( {
		page,
	} ) => {
		await setupEditor( page );

		await page
			.locator( 'button.gutenberg-kit-default-block-appender' )
			.click();

		// Type "Hello " then bold "World".
		await page.keyboard.type( 'Hello ' );
		await page.keyboard.press( 'ControlOrMeta+b' );
		await page.keyboard.type( 'World' );
		await page.keyboard.press( 'ControlOrMeta+b' );

		// Split between "Hello " and "World".
		await page.keyboard.press( 'Home' );
		for ( let i = 0; i < 6; i++ ) {
			await page.keyboard.press( 'ArrowRight' );
		}
		await page.keyboard.press( 'Enter' );

		let blocks = await getBlocks( page );
		expect( blocks ).toHaveLength( 2 );
		expect( blocks[ 0 ].attributes.content ).toBe( 'Hello ' );
		expect( blocks[ 1 ].attributes.content ).toBe(
			'<strong>World</strong>'
		);

		// Merge back.
		await page.keyboard.press( 'Home' );
		await page.keyboard.press( 'Backspace' );

		blocks = await getBlocks( page );
		expect( blocks ).toHaveLength( 1 );
		expect( blocks[ 0 ].attributes.content ).toBe(
			'Hello <strong>World</strong>'
		);
	} );
} );
