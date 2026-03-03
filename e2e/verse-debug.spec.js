import { test, expect } from '@playwright/test';
import EditorPage from './editor-page';

test( 'debug verse alignment', async ( { page } ) => {
	const editor = new EditorPage( page );
	await editor.setup();

	await editor.insertBlock( 'core/verse' );
	const verseInput = page.locator(
		'pre[aria-label="Block: Verse"][contenteditable="true"]'
	);
	await verseInput.click();
	await page.keyboard.type( 'A verse line' );

	await editor.selectBlock( 0 );

	// Check verse block type supports
	const verseSupports = await page.evaluate( () => {
		const blockType = window.wp.blocks.getBlockType( 'core/verse' );
		return {
			typographySupport: blockType?.supports?.typography,
			hasTypographyTextAlign:
				!! blockType?.supports?.typography?.textAlign,
		};
	} );
	console.log(
		'Verse supports.typography:',
		JSON.stringify( verseSupports.typographySupport )
	);
	console.log(
		'Has typography.textAlign support:',
		verseSupports.hasTypographyTextAlign
	);

	// Dump full block attributes BEFORE alignment
	const attrsBefore = await page.evaluate( () => {
		const blocks = window.wp.data.select( 'core/block-editor' ).getBlocks();
		return blocks[ 0 ]?.attributes;
	} );
	console.log( 'BEFORE:', JSON.stringify( attrsBefore ) );

	// Check how many "Align text" buttons exist
	const alignButtons = page.getByRole( 'button', { name: 'Align text' } );
	const count = await alignButtons.count();
	console.log( 'Number of "Align text" buttons:', count );

	// Set alignment
	await editor.setTextAlignment( 'Align text center' );

	// Small wait for state propagation
	await page.waitForTimeout( 200 );

	// Dump full block attributes AFTER alignment
	const attrsAfter = await page.evaluate( () => {
		const blocks = window.wp.data.select( 'core/block-editor' ).getBlocks();
		return blocks[ 0 ]?.attributes;
	} );
	console.log( 'AFTER:', JSON.stringify( attrsAfter ) );

	const textAlign = attrsAfter?.textAlign;
	const styleTextAlign = attrsAfter?.style?.typography?.textAlign;
	console.log( 'textAlign:', textAlign );
	console.log( 'style.typography.textAlign:', styleTextAlign );

	expect( textAlign ?? styleTextAlign ).toBe( 'center' );
} );
