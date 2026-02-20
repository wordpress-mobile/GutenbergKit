/**
 * External dependencies
 */
import { test, expect } from '@playwright/test';

/**
 * Internal dependencies
 */
import EditorPage from './editor-page';
import { credentials } from './wp-env-fixtures';

test.describe( 'Pattern Insertion (F.5)', () => {
	test( 'should fetch patterns from the WP REST API', async () => {
		// Verify that patterns are available from the wp-env backend,
		// even though GBK delivers them through the native inserter bridge
		// rather than the web inserter.
		const response = await fetch(
			`${ credentials.siteApiRoot }wp/v2/block-patterns/patterns`,
			{ headers: { Authorization: credentials.authHeader } }
		);
		expect( response.ok ).toBe( true );

		const patterns = await response.json();
		expect( patterns.length ).toBeGreaterThan( 0 );

		// Verify patterns have the expected structure.
		const first = patterns[ 0 ];
		expect( first ).toHaveProperty( 'name' );
		expect( first ).toHaveProperty( 'content' );
	} );

	test( 'should insert parsed pattern content into the editor', async ( {
		page,
	} ) => {
		const editor = new EditorPage( page );
		await editor.setup();

		// Fetch a pattern from the REST API.
		const response = await fetch(
			`${ credentials.siteApiRoot }wp/v2/block-patterns/patterns`,
			{ headers: { Authorization: credentials.authHeader } }
		);
		const patterns = await response.json();
		const pattern = patterns.find( ( p ) => p.content );

		// Parse and insert the pattern content via the data store.
		const blockCount = await page.evaluate( ( content ) => {
			const blocks = window.wp.blocks.parse( content );
			window.wp.data
				.dispatch( 'core/block-editor' )
				.insertBlocks( blocks );
			return blocks.length;
		}, pattern.content );

		expect( blockCount ).toBeGreaterThan( 0 );

		// Verify blocks appeared in the editor.
		const blocks = await editor.getBlocks();
		expect( blocks.length ).toBeGreaterThanOrEqual( blockCount );
	} );
} );
