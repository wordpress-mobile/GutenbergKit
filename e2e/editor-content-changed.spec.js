import { test, expect } from '@playwright/test';
import EditorPage from './editor-page';

test.describe( 'onEditorContentChanged', () => {
	test( 'notifies the host after the content changes', async ( { page } ) => {
		// Stand in for the Android bridge, which receives host events on
		// `window.editorDelegate` and answers the editor's request for the
		// host's latest content, here with none.
		await page.addInitScript( () => {
			window.contentChangedCount = 0;
			const replies = new EventTarget();
			window.editorDelegate = {
				addEventListener: replies.addEventListener.bind( replies ),
				removeEventListener:
					replies.removeEventListener.bind( replies ),
				postMessage: ( json ) => {
					const { message, body } = JSON.parse( json );
					if ( message === 'requestLatestContent' ) {
						const data = JSON.stringify( {
							message,
							body: { id: body.id, result: null },
						} );
						setTimeout( () =>
							replies.dispatchEvent(
								new MessageEvent( 'message', { data } )
							)
						);
					} else if ( message === 'onEditorContentChanged' ) {
						window.contentChangedCount++;
					}
				},
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
