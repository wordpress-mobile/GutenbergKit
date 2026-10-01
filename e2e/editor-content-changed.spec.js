import { test, expect } from '@playwright/test';
import EditorPage from './editor-page';

test.describe( 'onEditorContentChanged', () => {
	test( 'notifies the host after the content changes', async ( { page } ) => {
		// Stand in for the Android bridge, which receives host events on
		// `window.editorDelegate`.
		await page.addInitScript( () => {
			window.contentChangedCount = 0;
			window.editorDelegate = {
				onEditorContentChanged: () => window.contentChangedCount++,
			};
		} );

		const editor = new EditorPage( page );
		await editor.setup();

		await editor.clickBlockAppender();
		await page.keyboard.type( 'Hello' );

		await expect
			.poll( () => page.evaluate( () => window.contentChangedCount ) )
			.toBeGreaterThan( 0 );
	} );
} );
