/**
 * Page Object Model for the GutenbergKit editor.
 *
 * Encapsulates common editor interactions — setup, block appending,
 * caret movement, and data-store queries — behind a single class.
 */

/**
 * Internal dependencies
 */
import { credentials, getEditorSettings } from './wp-env-fixtures';

/**
 * Default GBKit configuration for wp-env testing.
 *
 * @type {Object}
 */
const DEFAULT_GBKIT = {
	siteApiRoot: credentials.siteApiRoot,
	authHeader: credentials.authHeader,
	siteApiNamespace: [],
	namespaceExcludedPaths: [],
	post: {
		id: 1,
		type: 'post',
		restBase: 'posts',
		restNamespace: 'wp/v2',
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
	 * @param {Object} [gbkit] Optional GBKit config override (merged with defaults).
	 */
	async setup( gbkit = {} ) {
		const editorSettings = await getEditorSettings();

		const config = {
			...DEFAULT_GBKIT,
			editorSettings,
			...gbkit,
			post: {
				...DEFAULT_GBKIT.post,
				...gbkit.post,
			},
		};

		await this.#page.addInitScript( ( cfg ) => {
			window.GBKit = cfg;
		}, config );

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
			null,
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
	 * Select all content in the currently focused block.
	 */
	async selectAll() {
		await this.#page.keyboard.press( 'ControlOrMeta+a' );
	}

	/**
	 * Click the Bold toolbar button to toggle bold formatting.
	 */
	async clickBold() {
		await this.#page.getByRole( 'button', { name: 'Bold' } ).click();
	}

	/**
	 * Click the Italic toolbar button to toggle italic formatting.
	 */
	async clickItalic() {
		await this.#page.getByRole( 'button', { name: 'Italic' } ).click();
	}

	/**
	 * Open the link popover via the toolbar button, type a URL, and submit.
	 *
	 * @param {string} url The URL to insert.
	 */
	async insertLink( url ) {
		await this.#page.getByRole( 'button', { name: 'Link' } ).click();

		const urlInput = this.#page.getByRole( 'combobox', {
			name: 'Search or type URL',
		} );
		await urlInput.waitFor( { state: 'visible' } );
		await urlInput.fill( url );
		await this.#page.keyboard.press( 'Enter' );
	}

	/**
	 * Insert a block via the data store.
	 *
	 * @param {string} name  Block name (e.g. 'core/paragraph').
	 * @param {Object} attrs Optional block attributes.
	 */
	async insertBlock( name, attrs = {} ) {
		await this.#page.evaluate(
			( { blockName, blockAttrs } ) => {
				const block = window.wp.blocks.createBlock(
					blockName,
					blockAttrs
				);
				window.wp.data
					.dispatch( 'core/block-editor' )
					.insertBlock( block );
			},
			{ blockName: name, blockAttrs: attrs }
		);
	}

	/**
	 * Select a block by its index in the root block list.
	 *
	 * @param {number} index Zero-based block index.
	 */
	async selectBlock( index ) {
		await this.#page.evaluate( ( idx ) => {
			const blocks = window.wp.data
				.select( 'core/block-editor' )
				.getBlocks();
			window.wp.data
				.dispatch( 'core/block-editor' )
				.selectBlock( blocks[ idx ].clientId );
		}, index );
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

	/**
	 * Read a single attribute from a root-level block.
	 *
	 * @param {number} index     Zero-based block index.
	 * @param {string} attribute Attribute name.
	 * @return {Promise<*>} The attribute value.
	 */
	async getBlockAttribute( index, attribute ) {
		return await this.#page.evaluate(
			( { idx, attr } ) => {
				const blocks = window.wp.data
					.select( 'core/block-editor' )
					.getBlocks();
				return blocks[ idx ]?.attributes?.[ attr ];
			},
			{ idx: index, attr: attribute }
		);
	}

	/**
	 * Open the "Align text" dropdown and select an alignment option.
	 *
	 * @param {string} alignment Alignment label (e.g. 'Align text center').
	 */
	async setTextAlignment( alignment ) {
		await this.#page.getByRole( 'button', { name: 'Align text' } ).click();
		await this.#page
			.getByRole( 'menuitemradio', { name: alignment } )
			.click();
	}

	/**
	 * Open the block settings popover (the "Block Settings" cog in the toolbar).
	 *
	 * The popover is only available when a block is selected.
	 */
	async openBlockSettings() {
		await this.#page
			.getByRole( 'button', { name: 'Block Settings' } )
			.click();
	}

	/**
	 * Wait for a media upload to complete on a block at the given index.
	 *
	 * Polls the block's `id` attribute until it becomes a positive number,
	 * indicating the upload has finished and the media was assigned a WP ID.
	 *
	 * @param {number} index   Zero-based block index.
	 * @param {number} timeout Max wait time in milliseconds.
	 * @return {Promise<Object>} The block's attributes after upload completes.
	 */
	async waitForMediaUpload( index, timeout = 30_000 ) {
		await this.#page.waitForFunction(
			( { idx } ) => {
				const blocks = window.wp.data
					.select( 'core/block-editor' )
					.getBlocks();
				const block = blocks[ idx ];
				return block?.attributes?.id > 0;
			},
			{ idx: index },
			{ timeout }
		);

		const blocks = await this.getBlocks();
		return blocks[ index ].attributes;
	}
}
