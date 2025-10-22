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
 * @param {Object} blockType The block type object.
 *
 * @return {string|null} The serialized icon string or null.
 */
function getBlockIcon( blockType ) {
	if ( ! blockType.icon ) {
		return null;
	}

	let iconSource = blockType.icon;

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
			debug(
				`Failed to render icon for block ${ blockType.name }`,
				error
			);
			return null;
		}
	} else if ( typeof iconSource === 'string' ) {
		return iconSource;
	}

	return null;
}

/**
 * Get serialized block data for all registered block types.
 *
 * @return {Array} Array of serialized block objects.
 */
export function getSerializedBlocks() {
	return getBlockTypes().map( ( blockType ) => {
		return {
			name: blockType.name,
			title: blockType.title,
			description: blockType.description,
			category: blockType.category,
			keywords: blockType.keywords || [],
			icon: getBlockIcon( blockType ),
		};
	} );
}
