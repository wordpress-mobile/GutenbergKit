/**
 * WordPress dependencies
 */
import { useEffect } from '@wordpress/element';
import { useSelect } from '@wordpress/data';
import { Button } from '@wordpress/components';
import { __ } from '@wordpress/i18n';
import { plus } from '@wordpress/icons';

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
						`Block with ID "${ blockId }" not found in inserter items`
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
		};

		return () => {
			delete window.blockInserter;
		};
	}, [ blocks, destinationBlockName, inserterItems, onSelectItem ] );

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
