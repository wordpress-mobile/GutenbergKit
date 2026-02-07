/**
 * Shared editor setup helper for E2E tests.
 *
 * Navigates to the editor in dev mode, injects the GBKit config, and waits
 * for the editor to reach a ready state.
 */

/**
 * Default GBKit configuration for dev-mode testing.
 *
 * @type {Object}
 */
const DEFAULT_GBKIT = {
	post: {
		id: -1,
		type: 'post',
		status: 'draft',
		title: '',
		content: '',
	},
};

/**
 * Navigate to the editor and wait for it to be fully ready.
 *
 * @param {import('@playwright/test').Page} page    Playwright page object.
 * @param {Object}                          [gbkit] Optional GBKit config override.
 */
export async function setupEditor( page, gbkit = DEFAULT_GBKIT ) {
	// Inject GBKit config before page scripts run.
	await page.addInitScript( ( config ) => {
		window.GBKit = config;
	}, gbkit );

	// Navigate to the editor in dev mode.
	await page.goto( '/?dev_mode=1' );

	// Wait for the visual editor container to be visible.
	await page.locator( '.gutenberg-kit-visual-editor' ).waitFor( {
		state: 'visible',
		timeout: 30_000,
	} );

	// Wait for WordPress editor data store to report ready.
	await page.waitForFunction(
		() =>
			window.wp?.data
				?.select( 'core/editor' )
				?.__unstableIsEditorReady?.(),
		{ timeout: 30_000 }
	);
}

/**
 * Retrieve all blocks from the editor via the WP data store.
 *
 * @param {import('@playwright/test').Page} page Playwright page object.
 * @return {Promise<Array>} Array of block objects.
 */
export async function getBlocks( page ) {
	return await page.evaluate( () =>
		window.wp.data.select( 'core/block-editor' ).getBlocks()
	);
}
