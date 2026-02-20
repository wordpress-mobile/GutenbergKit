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

		// Open block settings and navigate to the Styles tab.
		await editor.openBlockSettings();
		await page.getByRole( 'tab', { name: 'Styles' } ).click();

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

	test( 'should have theme gradients available in editor settings', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		// Verify that theme gradients are loaded from wp-env editor settings.
		const hasGradients = await page.evaluate( () => {
			const settings = window.wp.data
				.select( 'core/block-editor' )
				.getSettings();
			return (
				Array.isArray( settings.gradients ) &&
				settings.gradients.length > 0
			);
		} );
		expect( hasGradients ).toBe( true );
	} );

	test( 'should apply a gradient to a button via data store', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		await editor.insertBlock( 'core/buttons' );

		// Apply a gradient to the inner button block via the data store.
		await page.evaluate( () => {
			const blocks = window.wp.data
				.select( 'core/block-editor' )
				.getBlocks();
			const innerButton = blocks[ 0 ]?.innerBlocks?.[ 0 ];
			if ( innerButton ) {
				window.wp.data
					.dispatch( 'core/block-editor' )
					.updateBlockAttributes( innerButton.clientId, {
						gradient: 'vivid-cyan-blue-to-vivid-purple',
					} );
			}
		} );

		// Verify the gradient was applied.
		const blocks = await editor.getBlocks();
		const innerButton = blocks[ 0 ].innerBlocks[ 0 ];
		expect( innerButton.attributes.gradient ).toBe(
			'vivid-cyan-blue-to-vivid-purple'
		);
	} );
} );
