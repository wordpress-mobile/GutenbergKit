/**
 * WordPress dependencies
 */
import { Button } from '@wordpress/components';
import { __ } from '@wordpress/i18n';
import { plus } from '@wordpress/icons';
import { useSelect, useDispatch } from '@wordpress/data';
import { findTransform, getBlockTransforms, parse } from '@wordpress/blocks';
import { useRef } from '@wordpress/element';

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
import { store as blockEditorStore } from '@wordpress/block-editor';
import { debug } from '../../utils/logger';
import { preprocessBlockTypesForNativeInserter } from '../../utils/blocks';
import { showBlockInserter } from '../../utils/bridge';
import { unlock } from '../../lock-unlock';

/**
 * Native Block Inserter Button Component
 *
 * This component combines the block inserter button UI with the bridge logic
 * that manages block insertion state for native platforms. It uses WordPress
 * hooks (useInsertionPoint and useBlockTypesState) to manage block insertion
 * state and exposes the current inserter state globally for the native side.
 */
export default function NativeBlockInserterButton() {
	const buttonRef = useRef( null );

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

	const insertBlock = ( blockId ) => {
		const item = inserterItems.find( ( i ) => i.id === blockId );
		if ( ! item ) {
			debug( `Block with id "${ blockId }" not found in inserter items` );
			return false;
		}
		try {
			onSelectItem( item );
			return true;
		} catch ( error ) {
			debug( 'Failed to insert block:', error );
			return false;
		}
	};

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
	 * @param {Array} mediaArray Array of media objects with shape:
	 *                           { id?, url, type, caption?, alt?, title?, metadata? }
	 * @return {Promise<boolean>} True if insertion succeeded, false otherwise
	 */
	const insertMedia = async ( mediaArray ) => {
		if ( ! Array.isArray( mediaArray ) || mediaArray.length === 0 ) {
			return false;
		}
		try {
			// Convert media objects to File objects
			// This allows us to use the existing file transform system
			const files = await Promise.all(
				mediaArray.map( async ( media ) => {
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
					canInsertBlockType(
						transform.blockName,
						destinationRootClientId
					) &&
					transform.isMatch( validFiles )
			);

			if ( ! transformation ) {
				debug( 'insertMedia: No matching transform found', {
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
				debug( 'insertMedia: Transform produced no blocks' );
				return false;
			}

			onInsertBlocks( blocks );
			return true;
		} catch ( error ) {
			debug( 'insertMedia: Failed to insert media blocks', error );
			return false;
		}
	};

	const insertPattern = ( patternName ) => {
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
	};

	return (
		<Button
			ref={ buttonRef }
			title={ __( 'Add block' ) }
			icon={ plus }
			onClick={ () => {
				const sections = preprocessBlockTypesForNativeInserter(
					inserterItems,
					destinationBlockName,
					categories
				);

				// Format patterns for native consumption
				const formattedPatterns =
					patterns?.map( ( pattern ) => ( {
						name: pattern.name,
						title: pattern.title,
						content: pattern.content,
						blockTypes: pattern.blockTypes ?? null,
						categories: pattern.categories ?? null,
						description: pattern.description ?? null,
						keywords: pattern.keywords ?? null,
						source: pattern.source ?? null,
						viewportWidth: pattern.viewportWidth ?? null,
					} ) ) ?? [];

				window.blockInserter = {
					sections,
					patterns: formattedPatterns,
					insertBlock,
					insertPattern,
					insertMedia,
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
			} }
			onMouseDown={ ( e ) => {
				e.preventDefault();
			} }
			className="gutenberg-kit-add-block-button"
		/>
	);
}
