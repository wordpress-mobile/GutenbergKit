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
 * Predefined category ordering.
 */
const ORDERED_CATEGORIES = [
	{ key: 'text', displayName: 'Text' },
	{ key: 'media', displayName: 'Media' },
	{ key: 'design', displayName: 'Design' },
	{ key: 'widgets', displayName: 'Widgets' },
	{ key: 'theme', displayName: 'Theme' },
	{ key: 'embed', displayName: 'Embeds' },
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
	design: [
		'core/separator',
		'core/spacer',
		'core/columns',
		'core/column',
	],
};

/**
 * Most used blocks to show when there are no contextual blocks.
 */
const MOST_USED_BLOCKS = [
	'core/paragraph',
	'core/heading',
	'core/list',
	'core/quote',
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

	// Add blocks in predefined order
	for ( const name of order ) {
		const block = blocks.find( ( b ) => b.name === name );
		if ( block ) {
			orderedBlocks.push( block );
		}
	}

	// Add remaining blocks in their original order
	const remainingBlocks = blocks.filter(
		( block ) => ! order.includes( block.name )
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
 *
 * WARNING: This function eliminates 90+% of JSON payload by compacting
 * otherwise duplicated block variants. Do not add unnecessary properties
 * or modify the compact format without careful consideration of the
 * performance impact on the native bridge.
 *
 * @param {Array}  inserterItems        Array of block inserter items from WordPress.
 * @param {string} destinationBlockName Name of the parent block where new blocks will be inserted.
 *
 * @return {Array} Array of sections, each containing category, name, and blocks array.
 */
export function preprocessBlockTypesForNativeInserter(
	inserterItems,
	destinationBlockName = null
) {
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
			frecency: item.frecency || 0,
			isDisabled: item.isDisabled || false,
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

	// Determine blocks to show in contextual section
	const contextualSectionBlocks =
		contextualBlocks.length > 0
			? contextualBlocks
			: serializedBlocks.filter( ( block ) =>
					MOST_USED_BLOCKS.includes( block.name )
			  );

	// Group regular blocks by category
	const blocksByCategory = {};
	for ( const block of serializedBlocks ) {
		const category = block.category?.toLowerCase() || 'common';
		if ( ! blocksByCategory[ category ] ) {
			blocksByCategory[ category ] = [];
		}
		blocksByCategory[ category ].push( block );
	}

	const sections = [];

	// Add contextual section
	if ( contextualSectionBlocks.length > 0 ) {
		sections.push( {
			category: 'gbk-contextual',
			name: null,
			blocks: contextualSectionBlocks,
		} );
	}

	// Add blocks by category in predefined order
	for ( const { key: category, displayName } of ORDERED_CATEGORIES ) {
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

	// Add any remaining categories
	const knownCategories = ORDERED_CATEGORIES.map( ( c ) => c.key );
	for ( const [ category, blocks ] of Object.entries( blocksByCategory ) ) {
		if ( ! knownCategories.includes( category ) ) {
			sections.push( {
				category,
				name: category.charAt( 0 ).toUpperCase() + category.slice( 1 ),
				blocks,
			} );
		}
	}

	return sections;
}
