/**
 * WordPress dependencies
 */
import { unregisterBlockType, getBlockTypes } from '@wordpress/blocks';
import { renderToString } from '@wordpress/element';
import { debug } from './logger';

/**
 * Unregister blocks that are disallowed.
 *
 * @param {Array} allowedBlockTypes The list of allowed block types.
 */
export function unregisterDisallowedBlocks( allowedBlockTypes ) {
	if ( ! allowedBlockTypes ) {
		return;
	}

	const unregisteredBlocks = [];
	getBlockTypes().forEach( ( block ) => {
		if ( ! allowedBlockTypes.includes( block.name ) ) {
			unregisterBlockType( block.name );
			unregisteredBlocks.push( block.name );
		}
	} );

	debug( 'Blocks unregistered:', unregisteredBlocks );
}

/**
 * Extract and serialize a block's icon.
 *
 * @param {Object} item The block type or inserter item object.
 *
 * @return {string|null} The serialized icon string or null.
 */
export function getBlockIcon( item ) {
	if ( ! item.icon ) {
		return null;
	}

	let iconSource = item.icon;

	// If icon is an object with src property, extract src
	if ( typeof iconSource === 'object' && iconSource.src ) {
		iconSource = iconSource.src;
	}

	// Convert React element to SVG string
	if (
		typeof iconSource === 'object' &&
		iconSource !== null &&
		typeof iconSource.type !== 'undefined'
	) {
		try {
			return renderToString( iconSource );
		} catch ( error ) {
			// If rendering fails, ignore the icon
			debug( `Failed to render icon for block ${ item.name }`, error );
			return null;
		}
	} else if ( typeof iconSource === 'string' ) {
		return iconSource;
	}

	return null;
}

/**
 * Extract a block icon's foreground colour. Branded embed icons
 * (e.g. Pocket Casts, Spotify) declare their brand colour via an
 * `icon.foreground` property that the web editor applies as CSS
 * `color`, which paths inside the SVG inherit as `currentColor`.
 * Native renderers don't see the editor's CSS, so we pass the
 * colour through explicitly.
 *
 * @param {Object} item The block type or inserter item object.
 *
 * @return {string|null} Hex/CSS colour string or null.
 */
export function getBlockIconForeground( item ) {
	if (
		item?.icon &&
		typeof item.icon === 'object' &&
		typeof item.icon.foreground === 'string'
	) {
		return item.icon.foreground;
	}
	return null;
}

/**
 * Predefined category ordering.
 * Display names will be retrieved from WordPress categories for proper localization.
 */
const ORDERED_CATEGORIES = [
	{ key: 'text' },
	{ key: 'media' },
	{ key: 'design' },
	{ key: 'widgets' },
	{ key: 'theme' },
	{ key: 'embed' },
];

/**
 * Predefined block ordering within categories.
 */
const BLOCK_ORDER_BY_CATEGORY = {
	text: [
		'core/paragraph',
		'core/heading',
		'core/list',
		'core/list-item',
		'core/quote',
		'core/code',
		'core/preformatted',
		'core/verse',
		'core/table',
	],
	media: [
		'core/image',
		'core/video',
		'core/gallery',
		'core/embed',
		'core/audio',
		'core/file',
	],
	design: [ 'core/separator', 'core/spacer', 'core/columns', 'core/column' ],
	embed: [
		'core/embed', // Generic embed - always first
		'core/embed/youtube',
		'core/embed/vimeo',
		'core/embed/tiktok',
		'core/embed/wordpress',
		'core/embed/tumblr',
		'core/embed/videopress',
		'core/embed/pocket-casts',
		'core/embed/reddit',
		'core/embed/pinterest',
		'core/embed/spotify',
		'core/embed/soundcloud',
	],
};

/**
 * Most used blocks to show when there are no contextual blocks.
 * Optimized for mobile usage patterns where users frequently create content
 * with text, media from device cameras, and visual formatting.
 */
const MOST_USED_BLOCKS = [
	// Fundamentals
	'core/paragraph',
	'core/heading',
	'core/list',
	'core/quote',
	// Layout and more
	'core/table',
	'core/separator',
	'core/code',
	'core/preformatted',
	// Media blocks - very popular on mobile (camera/photo usage)
	'core/image',
	'core/gallery',
	'core/video',
	'core/embed',
];

/**
 * Orders blocks within a category according to predefined ordering.
 *
 * @param {Array}  blocks   Blocks to order.
 * @param {string} category Category key.
 *
 * @return {Array} Ordered blocks.
 */
function orderBlocksInCategory( blocks, category ) {
	const order = BLOCK_ORDER_BY_CATEGORY[ category ];
	if ( ! order ) {
		return blocks;
	}

	const orderedBlocks = [];

	// Add blocks in predefined order (using block ID for matching)
	for ( const id of order ) {
		const block = blocks.find( ( b ) => b.id === id );
		if ( block ) {
			orderedBlocks.push( block );
		}
	}

	// Add remaining blocks in their original order
	const remainingBlocks = blocks.filter(
		( block ) => ! order.includes( block.id )
	);

	return [ ...orderedBlocks, ...remainingBlocks ];
}

/**
 * Preprocesses inserter items for the native block inserter.
 * Organizes blocks into sections with proper ordering and contextual filtering.
 *
 * This function handles:
 * - Ordering blocks by category and within categories
 * - Creating a contextual section for blocks specifically allowed in the current parent
 * - Falling back to most-used blocks when no contextual blocks exist
 * - Serializing block data to a compact format for the native bridge
 * - Using localized category names from WordPress
 *
 * WARNING: This function eliminates 90+% of JSON payload by compacting
 * otherwise duplicated block variants. Do not add unnecessary properties
 * or modify the compact format without careful consideration of the
 * performance impact on the native bridge.
 *
 * @param {Array}  inserterItems        Array of block inserter items from WordPress.
 * @param {string} destinationBlockName Name of the parent block where new blocks will be inserted.
 * @param {Array}  categories           Array of category objects from WordPress with localized titles.
 *
 * @return {Array} Array of sections, each containing category, name, and blocks array.
 */
export function preprocessBlockTypesForNativeInserter(
	inserterItems,
	destinationBlockName = null,
	categories = []
) {
	// Build category map with localized names from WordPress
	// Falls back to hardcoded names if categories not provided
	const categoryMap = {};
	for ( const category of categories ) {
		categoryMap[ category.slug ] = category.title;
	}

	// Create ordered categories list with localized names
	const orderedCategories = ORDERED_CATEGORIES.map( ( { key } ) => ( {
		key,
		displayName:
			categoryMap[ key ] ||
			key.charAt( 0 ).toUpperCase() + key.slice( 1 ),
	} ) );

	// First, serialize all blocks
	const serializedBlocks = inserterItems.map( ( item ) => {
		return {
			id: item.id,
			name: item.name,
			title: item.title,
			description: item.description,
			category: item.category,
			keywords: item.keywords || [],
			icon: getBlockIcon( item ),
			iconForeground: getBlockIconForeground( item ),
			frecency: item.frecency || 0,
			isDisabled: item.isDisabled || false,
			isSearchOnly: item.isSearchOnly || false,
			parents: item.parent || [],
		};
	} );

	// Separate contextual blocks (specifically allowed in current parent block)
	const contextualBlocks = serializedBlocks.filter( ( block ) => {
		if ( ! destinationBlockName ) {
			return false;
		}
		return (
			block.parents.length > 0 &&
			block.parents.includes( destinationBlockName )
		);
	} );

	// Separate browsable blocks from search-only blocks (e.g. heading
	// level variations with scope 'block' that should appear in search
	// results but not in the browse view).
	const browsableBlocks = serializedBlocks.filter(
		( block ) => ! block.isSearchOnly
	);
	const searchOnlyBlocks = serializedBlocks.filter(
		( block ) => block.isSearchOnly
	);

	// Build most-used blocks in the order specified by MOST_USED_BLOCKS
	const mostUsedBlocks = [];
	for ( const blockName of MOST_USED_BLOCKS ) {
		const block = browsableBlocks.find( ( b ) => b.name === blockName );
		if ( block ) {
			mostUsedBlocks.push( block );
		}
	}

	// Group regular blocks by category
	const blocksByCategory = {};
	for ( const block of browsableBlocks ) {
		const category = block.category?.toLowerCase() || 'common';
		if ( ! blocksByCategory[ category ] ) {
			blocksByCategory[ category ] = [];
		}
		blocksByCategory[ category ].push( block );
	}

	const sections = [];

	// Add contextual section (only if there are parent-based contextual blocks)
	if ( contextualBlocks.length > 0 ) {
		sections.push( {
			category: 'gbk-contextual',
			name: null,
			blocks: contextualBlocks,
		} );
	}

	// Add most-used section (always shown)
	if ( mostUsedBlocks.length > 0 ) {
		sections.push( {
			category: 'gbk-most-used',
			name: null,
			blocks: mostUsedBlocks,
		} );
	}

	// Add blocks by category in predefined order
	for ( const { key: category, displayName } of orderedCategories ) {
		const blocks = blocksByCategory[ category ];
		if ( blocks ) {
			const orderedBlocks = orderBlocksInCategory( blocks, category );

			sections.push( {
				category,
				name: displayName,
				blocks: orderedBlocks,
			} );
		}
	}

	// Add any remaining categories with localized names if available
	const knownCategories = orderedCategories.map( ( c ) => c.key );
	for ( const [ category, blocks ] of Object.entries( blocksByCategory ) ) {
		if ( ! knownCategories.includes( category ) ) {
			sections.push( {
				category,
				name:
					categoryMap[ category ] ||
					category.charAt( 0 ).toUpperCase() + category.slice( 1 ),
				blocks,
			} );
		}
	}

	// Add search-only blocks as a hidden section. These blocks are excluded
	// from the browse view but should appear when the user searches.
	if ( searchOnlyBlocks.length > 0 ) {
		sections.push( {
			category: 'gbk-search-only',
			name: null,
			blocks: searchOnlyBlocks,
		} );
	}

	return sections;
}
