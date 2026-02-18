/**
 * External dependencies
 */
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import EditorPage from './editor-page';

test.describe( 'Buttons Block', () => {
	test( 'should insert buttons block and type text', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.insertBlock( 'core/buttons' );

		// The inner button block's rich-text placeholder should be focusable.
		const buttonText = page.getByRole( 'textbox', {
			name: 'Button text',
		} );
		await expect( buttonText ).toBeVisible();
		await buttonText.click();
		await page.keyboard.type( 'Click me' );

		const blocks = await editor.getBlocks();
		expect( blocks ).toHaveLength( 1 );
		expect( blocks[ 0 ].name ).toBe( 'core/buttons' );

		const innerBlocks = blocks[ 0 ].innerBlocks;
		expect( innerBlocks ).toHaveLength( 1 );
		expect( innerBlocks[ 0 ].name ).toBe( 'core/button' );
		expect( innerBlocks[ 0 ].attributes.text ).toBe( 'Click me' );
	} );

	test( 'should add a second button', async ( { page } ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.insertBlock( 'core/buttons' );

		// Type into the first button.
		const buttonText = page.getByRole( 'textbox', {
			name: 'Button text',
		} );
		await expect( buttonText ).toBeVisible();
		await buttonText.click();
		await page.keyboard.type( 'First' );

		// Press Enter to create a second button inside the Buttons block.
		await page.keyboard.press( 'Enter' );
		await page.keyboard.type( 'Second' );

		const blocks = await editor.getBlocks();
		const innerBlocks = blocks[ 0 ].innerBlocks;
		expect( innerBlocks ).toHaveLength( 2 );
		expect( innerBlocks[ 0 ].attributes.text ).toBe( 'First' );
		expect( innerBlocks[ 1 ].attributes.text ).toBe( 'Second' );
	} );
} );
