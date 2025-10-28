/**
 * WordPress dependencies
 */
import { useEffect } from '@wordpress/element';
import { useSelect, useDispatch } from '@wordpress/data';
import { Button } from '@wordpress/components';
import { __ } from '@wordpress/i18n';
import { plus } from '@wordpress/icons';
import {
	createBlock,
	findTransform,
	getBlockTransforms,
} from '@wordpress/blocks';

/**
 * Internal dependencies
 */
// NOTE: These hooks are internal WordPress APIs not available via public exports
// or privateApis. We import from build-module as the only way to access the
// block insertion logic without reimplementing it ourselves.
//
// Risks:
// - May break with WordPress package updates
// - No stability guarantees across versions
// - Not part of the public API contract
//
// Alternatives considered:
// - privateApis: These specific hooks are not exported there
// - Copying hooks: Too complex, uses multiple internal unlock() calls
// - Using PrivateQuickInserter component: Not suitable for headless bridge
//
// This approach is acceptable because:
// - We need the exact same insertion logic as the WordPress editor
// - The hooks are stable in practice (used by core components)
// - We're building a WordPress editor integration, not a general library
import useInsertionPoint from '@wordpress/block-editor/build-module/components/inserter/hooks/use-insertion-point';
import useBlockTypesState from '@wordpress/block-editor/build-module/components/inserter/hooks/use-block-types-state';
import { store as blockEditorStore } from '@wordpress/block-editor';
import { debug } from '../../utils/logger';
import { serializeBlocksForNative } from '../../utils/blocks';
import { showBlockInserter } from '../../utils/bridge';

/**
 * Native Block Inserter Button Component
 *
 * This component combines the block inserter button UI with the bridge logic
 * that manages block insertion state for native platforms. It uses WordPress
 * hooks (useInsertionPoint and useBlockTypesState) to manage block insertion
 * state and exposes the current inserter state globally for the native side.
 */
export default function NativeBlockInserterButton() {
	// Get current selection for insertion context and destination block info
	const { selectedBlockClientId, destinationBlockName } = useSelect(
		( select ) => {
			const { getSelectedBlockClientId, getBlockRootClientId, getBlock } =
				select( blockEditorStore );
			const clientId = getSelectedBlockClientId();
			// Get the parent block's client ID
			const parentClientId = clientId
				? getBlockRootClientId( clientId )
				: null;
			// Get the parent block object to extract its name
			const parentBlock = parentClientId
				? getBlock( parentClientId )
				: null;
			return {
				selectedBlockClientId: clientId,
				destinationBlockName: parentBlock?.name || null,
			};
		},
		[]
	);

	const { updateBlockAttributes } = useDispatch( blockEditorStore );

	// When cursor is in title, selectedBlockClientId is null.
	// Use undefined to insert at the beginning of content.
	const [ destinationRootClientId, onInsertBlocks ] = useInsertionPoint( {
		rootClientId: selectedBlockClientId ?? undefined,
		isAppender: false,
		selectBlockOnInsert: true,
	} );

	const [ inserterItems, , , onSelectItem ] = useBlockTypesState(
		destinationRootClientId,
		onInsertBlocks,
		false // isQuick
	);

	// Serialize blocks for native consumption
	const blocks = serializeBlocksForNative( inserterItems );

	// Expose the current inserter state globally for native access
	// This automatically stays in sync with editor state via hooks
	useEffect( () => {
		window.blockInserter = {
			blocks,
			destinationBlockName,
			insertBlock: ( blockId ) => {
				const item = inserterItems.find( ( i ) => i.id === blockId );
				if ( ! item ) {
					debug(
						`Block with id "${ blockId }" not found in inserter items`
					);
					return false;
				}

				try {
					// Use the hook's onSelectItem which handles all insertion logic
					onSelectItem( item );
					return true;
				} catch ( error ) {
					debug( 'Failed to insert block:', error );
					return false;
				}
			},
			/**
			 * Insert media blocks from native media picker using block transforms.
			 *
			 * This method uses the same file transform system as drag-and-drop,
			 * ensuring consistent behavior and leveraging WordPress's extensibility:
			 * - Finds matching transform based on file types (image/video/audio)
			 * - Respects transform priorities (gallery > single image)
			 * - Supports third-party block transforms
			 * - Handles block insertion validation
			 *
			 * Flow:
			 * 1. Convert media URLs to File objects
			 * 2. Find matching transform via findTransform()
			 * 3. Transform files to blocks
			 * 4. Insert blocks using onInsertBlocks
			 *
			 * @param {Array} mediaArray Array of media objects with shape:
			 *                           { id?, url, type, caption?, alt?, title?, metadata? }
			 * @return {Promise<boolean>} True if insertion succeeded, false otherwise
			 */
			insertMedia: async ( mediaArray ) => {
				if ( ! Array.isArray( mediaArray ) || mediaArray.length === 0 ) {
					debug( 'insertMedia: Invalid or empty media array' );
					return false;
				}

				try {
					debug( 'insertMedia: Processing media array', {
						count: mediaArray.length,
						types: mediaArray.map( ( m ) => m.type ),
					} );

					// Convert media objects to File objects
					// This allows us to use the existing file transform system
					const files = await Promise.all(
						mediaArray.map( async ( media ) => {
							try {
								// Fetch the media URL to get blob
								const response = await fetch( media.url );
								const blob = await response.blob();

								// Determine filename and MIME type
								const filename = media.title || 'media';
								const extension =
									media.type === 'video'
										? 'mp4'
										: media.type === 'audio'
										? 'mp3'
										: 'jpg';
								const mimeType =
									blob.type ||
									( media.type
										? `${ media.type }/`
										: 'image/jpeg' );

								// Create File object from blob
								return new File( [ blob ], `${ filename }.${ extension }`, {
									type: mimeType,
								} );
							} catch ( error ) {
								debug(
									`insertMedia: Failed to fetch media: ${ media.url }`,
									error
								);
								return null;
							}
						} )
					);

					// Filter out any failed fetches
					const validFiles = files.filter( ( f ) => f !== null );

					if ( validFiles.length === 0 ) {
						debug( 'insertMedia: No valid files to insert' );
						return false;
					}

					// Find matching transform using WordPress's transform system
					// This is the same logic as onFilesDrop in use-on-block-drop
					const transformation = findTransform(
						getBlockTransforms( 'from' ),
						( transform ) =>
							transform.type === 'files' &&
							transform.isMatch &&
							transform.isMatch( validFiles )
					);

					if ( ! transformation ) {
						debug( 'insertMedia: No matching transform found', {
							fileCount: validFiles.length,
							fileTypes: validFiles.map( ( f ) => f.type ),
						} );
						return false;
					}

					debug( 'insertMedia: Found transform', {
						blockName: transformation.blockName,
						priority: transformation.priority,
					} );

					// Use the transform to create blocks
					// The transform handles:
					// - Single image/video/audio → single block
					// - Multiple images → gallery block
					// - Blob URL creation for immediate preview
					const blocks = transformation.transform(
						validFiles,
						updateBlockAttributes
					);

					if ( ! blocks || ( Array.isArray( blocks ) && blocks.length === 0 ) ) {
						debug( 'insertMedia: Transform produced no blocks' );
						return false;
					}

					debug( 'insertMedia: Transform created blocks', {
						blockCount: Array.isArray( blocks )
							? blocks.length
							: 1,
						blockNames: Array.isArray( blocks )
							? blocks.map( ( b ) => b.name )
							: [ blocks.name ],
					} );

					// Insert blocks using the same mechanism as the inserter
					onInsertBlocks( blocks );
					debug( 'insertMedia: Blocks inserted successfully' );
					return true;
				} catch ( error ) {
					debug( 'insertMedia: Failed to insert media blocks', error );
					return false;
				}
			},
		};

		return () => {
			delete window.blockInserter;
		};
	}, [
		blocks,
		destinationBlockName,
		inserterItems,
		onSelectItem,
		onInsertBlocks,
		updateBlockAttributes,
	] );

	return (
		<Button
			title={ __( 'Add block' ) }
			icon={ plus }
			onClick={ ( e ) => {
				e.preventDefault();
				showBlockInserter();
			} }
			className="gutenberg-kit-add-block-button"
		/>
	);
}
