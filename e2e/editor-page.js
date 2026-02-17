/**
 * Page Object Model for the GutenbergKit editor.
 *
 * Encapsulates common editor interactions — setup, block appending,
 * caret movement, and data-store queries — behind a single class.
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

export default class EditorPage {
	/** @type {import('@playwright/test').Page} */
	#page;

	/**
	 * @param {import('@playwright/test').Page} page Playwright page object.
	 */
	constructor( page ) {
		this.#page = page;
	}

	/**
	 * Navigate to the editor and wait for it to be fully ready.
	 *
	 * @param {Object} [gbkit] Optional GBKit config override.
	 */
	async setup( gbkit = DEFAULT_GBKIT ) {
		await this.#page.addInitScript( ( config ) => {
			window.GBKit = config;
		}, gbkit );

		await this.#page.goto( '/?dev_mode=1' );

		await this.#page.locator( '.gutenberg-kit-visual-editor' ).waitFor( {
			state: 'visible',
			timeout: 30_000,
		} );

		await this.#page.waitForFunction(
			() =>
				window.wp?.data
					?.select( 'core/editor' )
					?.__unstableIsEditorReady?.(),
			{ timeout: 30_000 }
		);
	}

	/**
	 * Click the default block appender to create a new paragraph block.
	 */
	async clickBlockAppender() {
		await this.#page
			.getByRole( 'button', { name: 'Add paragraph block' } )
			.click();
	}

	/**
	 * Move the caret to the given character position in the current block.
	 *
	 * Uses Home to jump to the start, then ArrowRight to advance. This avoids
	 * off-by-one issues that ArrowLeft loops can hit at format boundaries.
	 *
	 * @param {number} position Zero-based character offset.
	 */
	async moveCaretTo( position ) {
		await this.#page.keyboard.press( 'Home' );
		for ( let i = 0; i < position; i++ ) {
			await this.#page.keyboard.press( 'ArrowRight' );
		}
	}

	/**
	 * Retrieve all blocks from the editor via the WP data store.
	 *
	 * @return {Promise<Array>} Array of block objects.
	 */
	async getBlocks() {
		return await this.#page.evaluate( () =>
			window.wp.data.select( 'core/block-editor' ).getBlocks()
		);
	}
}
