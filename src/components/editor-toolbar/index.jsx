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
import { close, cog } from '@wordpress/icons';
import clsx from 'clsx';
import { store as editorStore } from '@wordpress/editor';

/**
 * Internal dependencies
 */
import './style.scss';
import { useModalize } from './use-modalize';

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
		// opening a adjacent popover.
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
					<Inserter
						popoverProps={ {
							'aria-modal': true,
							role: 'dialog',
						} }
						open={ isInserterOpened }
						onToggle={ setIsInserterOpened }
					/>
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
