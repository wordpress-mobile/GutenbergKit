/**
 * WordPress dependencies
 */
import { useState, useRef } from '@wordpress/element';
import {
	BlockInspector,
	BlockToolbar,
	Inserter,
	store as blockEditorStore,
} from '@wordpress/block-editor';
import { useSelect, useDispatch } from '@wordpress/data';
import {
	Popover,
	Toolbar,
	ToolbarGroup,
	ToolbarButton,
} from '@wordpress/components';
import { __ } from '@wordpress/i18n';
import { cog } from '@wordpress/icons';
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
const EditorToolbar = ({ className }) => {
	const [isBlockInspectorShown, setBlockInspectorShown] = useState(false);
	const containerRef = useRef(null);
	const [popoverAnchor, setPopoverAnchor] = useState(null);
	const { isSelected } = useSelect((select) => {
		const { getSelectedBlockClientId } = select(blockEditorStore);
		const selectedBlockClientId = getSelectedBlockClientId();
		return {
			isSelected: selectedBlockClientId !== null,
		};
	});
	const { isInserterOpened } = useSelect((select) => {
		return {
			isInserterOpened: select(editorStore).isInserterOpened(),
		};
	}, []);
	const { setIsInserterOpened } = useDispatch(editorStore);

	useModalize(isInserterOpened);
	useModalize(isBlockInspectorShown);

	/**
	 * Closes the popover when focus leaves it unless the toggle was pressed or
	 * focus has moved to a separate dialog. The former is to let the toggle
	 * handle closing the popover and the latter is to preserve presence in
	 * case a dialog has opened, allowing focus to return when it's dismissed.
	 */
	function closeIfFocusOutside() {
		if (!containerRef.current) {
			return;
		}

		const { ownerDocument } = containerRef.current;
		const dialog = ownerDocument?.activeElement?.closest('[role="dialog"]');
		if (
			!containerRef.current.contains(ownerDocument.activeElement) &&
			(!dialog || dialog.contains(containerRef.current))
		) {
			setBlockInspectorShown(false);
		}
	}

	const classes = clsx('gutenberg-kit-editor-toolbar', className);

	return (
		<>
			<Toolbar
				className={classes}
				label="Editor toolbar"
				variant="unstyled"
			>
				<ToolbarGroup>
					<Inserter
						popoverProps={{
							'aria-modal': true,
							role: 'dialog',
						}}
						open={isInserterOpened}
						onToggle={setIsInserterOpened}
					/>
				</ToolbarGroup>

				{isSelected && (
					// Some UAs focus the closest focusable parent when the toggle is
					// clicked. Making this div focusable ensures such UAs will focus
					// it and `closeIfFocusOutside` can tell if the toggle was clicked.
					<div ref={containerRef} tabIndex="-1">
						<ToolbarGroup>
							<ToolbarButton
								ref={setPopoverAnchor}
								title={__('Open Settings')}
								icon={cog}
								onClick={() =>
									setBlockInspectorShown(
										(previous) => !previous
									)
								}
							/>
						</ToolbarGroup>

						{isSelected && isBlockInspectorShown && (
							<Popover
								anchor={popoverAnchor}
								aria-modal
								className="block-settings-menu"
								expandOnMobile
								offset={13}
								headerTitle={__('Block settings')}
								onFocusOutside={closeIfFocusOutside}
								onClick={() => setBlockInspectorShown(false)}
								role="dialog"
							>
								<BlockInspector />
							</Popover>
						)}
						<Popover.Slot name="" />
					</div>
				)}

				<BlockToolbar hideDragHandle />
			</Toolbar>
		</>
	);
};

export default EditorToolbar;
