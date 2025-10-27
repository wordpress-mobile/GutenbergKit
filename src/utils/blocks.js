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
 * Serializes inserter items to a format suitable for native consumption.
 * Extracts only the properties needed by the native side and ensures
 * proper formatting (e.g., converting React icon elements to SVG strings).
 *
 * @param {Array} inserterItems Array of block inserter items from WordPress.
 *
 * @return {Array} Array of serialized block objects for native consumption.
 */
export function serializeBlocksForNative( inserterItems ) {
	return inserterItems.map( ( item ) => {
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
}
