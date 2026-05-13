/**
 * WordPress dependencies
 */
import { Button } from '@wordpress/components';
import { __ } from '@wordpress/i18n';
import { plus } from '@wordpress/icons';
import { useSelect, useDispatch } from '@wordpress/data';
import {
	findTransform,
	getBlockTransforms,
	parse,
	createBlock,
} from '@wordpress/blocks';
import { getBlockAndPreviewFromMedia } from '@wordpress/block-editor/build-module/components/inserter/media-tab/utils';
import { useRef, useEffect, useCallback } from '@wordpress/element';
import { store as blockEditorStore } from '@wordpress/block-editor';
import { store as coreDataStore } from '@wordpress/core-data';
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

/**
 * Internal dependencies
 */
import { debug } from '../../utils/logger';
import {
	preprocessBlockTypesForNativeInserter,
	formatPatternsForNativeInserter,
	formatPatternCategoriesForNativeInserter,
} from '../../utils/blocks';
import { showBlockInserter } from '../../utils/bridge';
import { unlock } from '../../lock-unlock';

/**
 * Native Block Inserter Button Component
 *
 * This component combines the block inserter button UI with the bridge logic
 * that manages block insertion state for native platforms. It uses WordPress
 * hooks (useInsertionPoint and useBlockTypesState) to manage block insertion
 * state and exposes the current inserter state globally for the native side.
 *
 * Mimics the WordPress Inserter component API with open/onToggle props.
 *
 * @param {Object}   props          Component props
 * @param {boolean}  props.open     Whether the inserter is open
 * @param {Function} props.onToggle Callback to toggle inserter open state
 */
export default function NativeBlockInserterButton( { open, onToggle } ) {
	const buttonRef = useRef( null );
	const prevOpen = useRef( false );

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

	const { canInsertBlockType } = useSelect( blockEditorStore );

	const { updateBlockAttributes } = useDispatch( blockEditorStore );

	// When cursor is in title, selectedBlockClientId is null.
	// Use undefined to insert at the beginning of content.
	const [ destinationRootClientId, onInsertBlocks ] = useInsertionPoint( {
		rootClientId: selectedBlockClientId ?? undefined,
		isAppender: false,
		selectBlockOnInsert: true,
	} );

	const [ inserterItems, categories, , onSelectItem ] = useBlockTypesState(
		destinationRootClientId,
		onInsertBlocks,
		false // isQuick
	);

	// Get patterns for the inserter
	const patterns = useSelect(
		( select ) => {
			const { __experimentalGetAllowedPatterns } = unlock(
				select( blockEditorStore )
			);
			return __experimentalGetAllowedPatterns( destinationRootClientId );
		},
		[ destinationRootClientId ]
	);

	// Get pattern categories with localized labels
	const patternCategories = useSelect( ( select ) => {
		const { getBlockPatternCategories, getUserPatternCategories } =
			select( coreDataStore );

		return [
			...( getBlockPatternCategories() || [] ),
			...( getUserPatternCategories() || [] ),
		];
	}, [] );

	const insertBlock = useCallback(
		( blockId ) => {
			const item = inserterItems.find( ( i ) => i.id === blockId );
			if ( ! item ) {
				debug(
					`Block with id "${ blockId }" not found in inserter items`
				);
				return false;
			}
			try {
				onSelectItem( item );
				return true;
			} catch ( error ) {
				debug( 'Failed to insert block:', error );
				return false;
			}
		},
		[ inserterItems, onSelectItem ]
	);

	const insertPattern = useCallback(
		( patternName ) => {
			const pattern = patterns?.find( ( p ) => p.name === patternName );
			if ( ! pattern ) {
				debug( `Pattern "${ patternName }" not found` );
				return false;
			}

			try {
				// Parse and insert pattern blocks
				const blocks = parse( pattern.content );
				onInsertBlocks( blocks );
				return true;
			} catch ( error ) {
				debug( 'Failed to insert pattern:', error );
				return false;
			}
		},
		[ patterns, onInsertBlocks ]
	);

	const insertMedia = useCallback(
		async ( mediaArray ) => {
			if ( ! Array.isArray( mediaArray ) || mediaArray.length === 0 ) {
				return false;
			}

			/**
			 * Get media type from MIME type.
			 *
			 * @param {string} mimeType The MIME type of the media
			 * @return {string|null} Media type ('image', 'video', 'audio') or null
			 */
			const getMediaType = ( mimeType ) => {
				if ( ! mimeType ) {
					return null;
				}
				if ( mimeType.startsWith( 'image/' ) ) {
					return 'image';
				}
				if ( mimeType.startsWith( 'video/' ) ) {
					return 'video';
				}
				if ( mimeType.startsWith( 'audio/' ) ) {
					return 'audio';
				}
				return null;
			};

			/**
			 * Insert media from WordPress media library (with existing IDs).
			 * Creates blocks directly with media attributes, avoiding re-upload.
			 *
			 * @param {Array} items Array of media objects with IDs
			 * @return {boolean} True if insertion succeeded
			 */
			const insertMediaWithIds = ( items ) => {
				const blocks = [];
				const allImages = items.every(
					( media ) => getMediaType( media.type ) === 'image'
				);

				// Create gallery for multiple images
				if ( allImages && items.length > 1 ) {
					if (
						! canInsertBlockType(
							'core/gallery',
							destinationRootClientId
						)
					) {
						debug( 'Cannot insert gallery block at this location' );
						return false;
					}

					const galleryBlock = createBlock( 'core/gallery', {
						images: items.map( ( media ) => ( {
							id: String( media.id ),
							url: media.url,
							alt: media.alt ?? '',
							caption: media.caption ?? '',
						} ) ),
					} );
					blocks.push( galleryBlock );
				} else {
					// Create individual blocks using WordPress utility
					for ( const media of items ) {
						const mediaType = getMediaType( media.type );
						if ( ! mediaType ) {
							debug( `Unsupported media type: ${ media.type }` );
							continue;
						}

						if (
							! canInsertBlockType(
								`core/${ mediaType }`,
								destinationRootClientId
							)
						) {
							debug(
								`Cannot insert core/${ mediaType } block at this location`
							);
							continue;
						}

						const [ block ] = getBlockAndPreviewFromMedia(
							media,
							mediaType
						);
						blocks.push( block );
					}
				}

				if ( blocks.length === 0 ) {
					return false;
				}

				onInsertBlocks( blocks );
				return true;
			};

			/**
			 * Insert new media files (without IDs) using WordPress file transforms.
			 * Downloads files and uses transform system for block creation and upload.
			 *
			 * @param {Array} items Array of media objects without IDs
			 * @return {Promise<boolean>} True if insertion succeeded
			 */
			const insertMediaWithoutIds = async ( items ) => {
				// Convert media objects to File objects
				const files = await Promise.all(
					items.map( async ( media ) => {
						try {
							const response = await fetch( media.url );
							const blob = await response.blob();
							const filename =
								media.url.split( '/' ).pop() || 'media';
							return new File( [ blob ], filename, {
								type: media.type ?? 'application/octet-stream',
							} );
						} catch ( error ) {
							debug(
								`Failed to fetch media: ${ media.url }`,
								error
							);
							return null;
						}
					} )
				);

				const validFiles = files.filter( ( f ) => f !== null );
				if ( validFiles.length === 0 ) {
					debug( 'No valid files to insert' );
					return false;
				}

				// Find and apply file transform
				const transformation = findTransform(
					getBlockTransforms( 'from' ),
					( transform ) =>
						transform.type === 'files' &&
						canInsertBlockType(
							transform.blockName,
							destinationRootClientId
						) &&
						transform.isMatch( validFiles )
				);

				if ( ! transformation ) {
					debug( 'No matching transform found', {
						fileCount: validFiles.length,
						fileTypes: validFiles.map( ( f ) => f.type ),
					} );
					return false;
				}

				const blocks = transformation.transform(
					validFiles,
					updateBlockAttributes
				);

				if (
					! blocks ||
					( Array.isArray( blocks ) && blocks.length === 0 )
				) {
					debug( 'Transform produced no blocks' );
					return false;
				}

				onInsertBlocks( Array.isArray( blocks ) ? blocks : [ blocks ] );
				return true;
			};

			try {
				// Assume all media have IDs or all don't (not mixed)
				const hasIds = mediaArray[ 0 ]?.id;

				return hasIds
					? insertMediaWithIds( mediaArray )
					: await insertMediaWithoutIds( mediaArray );
			} catch ( error ) {
				debug( 'Failed to insert media blocks', error );
				return false;
			}
		},
		[
			canInsertBlockType,
			destinationRootClientId,
			onInsertBlocks,
			updateBlockAttributes,
		]
	);

	const prepareAndShowInserter = useCallback( () => {
		const sections = preprocessBlockTypesForNativeInserter(
			inserterItems,
			destinationBlockName,
			categories
		);

		const formattedPatterns = formatPatternsForNativeInserter( patterns );
		const formattedPatternCategories =
			formatPatternCategoriesForNativeInserter( patternCategories );

		window.blockInserter = {
			sections,
			patterns: formattedPatterns,
			patternCategories: formattedPatternCategories,
			insertBlock,
			insertPattern,
			insertMedia,
			onClose: () => {
				onToggle( false );
				return true; // Return valid result type for the native host
			},
		};

		// Get button position for popover presentation on iPad
		let sourceRect;
		if ( buttonRef.current ) {
			const rect = buttonRef.current.getBoundingClientRect();
			sourceRect = {
				x: rect.left,
				y: rect.top,
				width: rect.width,
				height: rect.height,
			};
		}

		showBlockInserter( sourceRect );
	}, [
		inserterItems,
		destinationBlockName,
		categories,
		patterns,
		patternCategories,
		insertBlock,
		insertPattern,
		insertMedia,
		onToggle,
	] );

	// Watch for controlled open state changes
	useEffect( () => {
		// Only trigger when transitioning from false to true
		if ( open && ! prevOpen.current ) {
			prepareAndShowInserter();
		}
		prevOpen.current = open;
	}, [ open, prepareAndShowInserter ] );

	return (
		<Button
			ref={ buttonRef }
			title={ __( 'Add block' ) }
			icon={ plus }
			onClick={ () => {
				// Skip the redux toggle and present the native inserter
				// directly. Flipping `isInserterOpened` in editorStore would
				// briefly render Gutenberg's web inserter behind the native
				// dialog before it covers, causing a visible flash.
				prepareAndShowInserter();
			} }
			onMouseDown={ ( e ) => {
				e.preventDefault();
			} }
			className="gutenberg-kit-add-block-button"
		/>
	);
}
