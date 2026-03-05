/**
 * External dependencies
 */
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import EditorPage from './editor-page';

test.describe( 'Color and Gradient', () => {
	test( 'should apply a background color to a button via settings', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.insertBlock( 'core/buttons' );

		// Type into the button so the inner button block is focused.
		const buttonText = page.getByRole( 'textbox', {
			name: 'Button text',
		} );
		await buttonText.click();
		await page.keyboard.type( 'Colored' );

		// Open block settings.
		await editor.openBlockSettings();

		// Click the Background color control.
		await page
			.locator( '.block-settings-menu' )
			.getByRole( 'button', { name: 'Background' } )
			.click();

		// Pick the first color option in the palette.
		await page
			.locator( '.components-circular-option-picker__option' )
			.first()
			.click();

		// Close the settings popover before reading attributes.
		await page.keyboard.press( 'Escape' );

		// Verify the inner button block got a background color.
		const blocks = await editor.getBlocks();
		const innerButton = blocks[ 0 ].innerBlocks[ 0 ];
		expect(
			innerButton.attributes.backgroundColor ||
				innerButton.attributes.style?.color?.background
		).toBeTruthy();
	} );
} );
