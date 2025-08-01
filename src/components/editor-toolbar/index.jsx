/**
 * WordPress dependencies
 */
import { useState } from '@wordpress/element';
import {
	BlockInspector,
	BlockToolbar,
	Inserter,
	store as blockEditorStore,
} from '@wordpress/block-editor';
import { useSelect, useDispatch } from '@wordpress/data';
import {
	Button,
	Popover,
	Toolbar,
	ToolbarGroup,
	ToolbarButton,
} from '@wordpress/components';
import { __ } from '@wordpress/i18n';
import { close, cog, plus } from '@wordpress/icons';
import clsx from 'clsx';
import { store as editorStore } from '@wordpress/editor';

/**
 * Internal dependencies
 */
import './style.scss';
import { useModalize } from './use-modalize';
import { showBlockPicker, getGBKit } from '../../utils/bridge';

/**
 * Renders the editor toolbar containing block-related actions.
 *
 * @param {Object} props           Component props.
 * @param {string} props.className Component classes.
 * @return {JSX.Element} The rendered editor toolbar component.
 */
const EditorToolbar = ( { className } ) => {
	const [ isBlockInspectorShown, setBlockInspectorShown ] = useState( false );
	const { isSelected } = useSelect( ( select ) => {
		const { getSelectedBlockClientId } = select( blockEditorStore );
		const selectedBlockClientId = getSelectedBlockClientId();
		return {
			isSelected: selectedBlockClientId !== null,
		};
	} );
	const { isInserterOpened } = useSelect( ( select ) => {
		return {
			isInserterOpened: select( editorStore ).isInserterOpened(),
		};
	}, [] );
	const { setIsInserterOpened } = useDispatch( editorStore );

	// Check if native block inserter is enabled from configuration
	const gbKit = getGBKit();
	const enableNativeBlockInserter = gbKit.enableNativeBlockInserter ?? false;

	useModalize( isInserterOpened );
	useModalize( isBlockInspectorShown );

	function openSettings() {
		setBlockInspectorShown( true );
	}

	function onCloseSettings() {
		setBlockInspectorShown( false );
	}

	function onFocusOutside( event ) {
		// Do not close the menu if the focus is inside the menu--e.g., a button
		// opening an adjacent popover.
		if ( event.target.closest( '.block-settings-menu' ) ) {
			return;
		}

		setBlockInspectorShown( false );
	}

	const classes = clsx( 'gutenberg-kit-editor-toolbar', className );

	return (
		<>
			<Toolbar
				className={ classes }
				label="Editor toolbar"
				variant="unstyled"
			>
				<ToolbarGroup>
					{ enableNativeBlockInserter ? (
						<ToolbarButton
							title={ __( 'Add block' ) }
							icon={ plus }
							onClick={ () => {
								// Close any open web inserter
								if ( isInserterOpened ) {
									setIsInserterOpened( false );
								}
								// Show native block picker
								showBlockPicker();
							} }
							className="gutenberg-kit-add-block-button"
						/>
					) : (
						<Inserter
							popoverProps={ {
								'aria-modal': true,
								role: 'dialog',
							} }
							isAppender
							showInserterHelpPanel
						/>
					) }
				</ToolbarGroup>

				{ isSelected && (
					<ToolbarGroup>
						<ToolbarButton
							title={ __( 'Block Settings' ) }
							icon={ cog }
							onClick={ openSettings }
						/>
					</ToolbarGroup>
				) }

				<BlockToolbar hideDragHandle />
			</Toolbar>

			{ isBlockInspectorShown && (
				<Popover
					className="block-settings-menu"
					variant="unstyled"
					placement="overlay"
					aria-modal
					onClose={ onCloseSettings }
					onFocusOutside={ onFocusOutside }
					role="dialog"
				>
					<>
						<div className="block-settings-menu__header">
							<Button
								className="block-settings-menu__close"
								icon={ close }
								onClick={ onCloseSettings }
							/>
						</div>
						<BlockInspector />
					</>
				</Popover>
			) }
		</>
	);
};

export default EditorToolbar;
