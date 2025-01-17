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
import { close, cog, keyboardClose } from '@wordpress/icons';
import clsx from 'clsx';

/**
 * Internal dependencies
 */
import './style.scss';
import { useKeyboardVisibility } from './use-keyboard-visibility';

/**
 * Renders the editor toolbar containing block-related actions.
 *
 * @param {Object} props           Component props.
 * @param {string} props.className Component classes.
 * @return {JSX.Element} The rendered editor toolbar component.
 */
const EditorToolbar = ({ className }) => {
	const [isBlockInspectorShown, setBlockInspectorShown] = useState(false);
	const { isSelected } = useSelect((select) => {
		const { getSelectedBlockClientId } = select(blockEditorStore);
		const selectedBlockClientId = getSelectedBlockClientId();
		return {
			isSelected: selectedBlockClientId !== null,
		};
	});
	const { clearSelectedBlock } = useDispatch(blockEditorStore);

	function openSettings() {
		setBlockInspectorShown(true);
	}

	function onCloseSettings() {
		setBlockInspectorShown(false);
	}

	const classes = clsx('gutenberg-kit-editor-toolbar', className);

	const [isKeyboardVisible, setIsKeyboardVisible] = useKeyboardVisibility();
	const shadowClasses = clsx(' gutenberg-kit-editor-toolbar__shadow', {
		'is-keyboard-visible': isKeyboardVisible,
	});

	return (
		<>
			<Toolbar
				className={classes}
				label="Editor toolbar"
				variant="unstyled"
			>
				<div className="gutenberg-kit-editor-toolbar__scroll-view">
					<ToolbarGroup>
						<Inserter />
					</ToolbarGroup>

					{isSelected && (
						<ToolbarGroup>
							<ToolbarButton
								title={__('Open Settings')}
								icon={cog}
								onClick={openSettings}
							/>
						</ToolbarGroup>
					)}

					<BlockToolbar hideDragHandle />
				</div>

				<div className={shadowClasses} />

				{isKeyboardVisible && (
					<ToolbarGroup className="gutenberg-kit-editor-toolbar__keyboard-close">
						<ToolbarButton
							title={__('Dismiss keyboard')}
							icon={keyboardClose}
							onClick={() => {
								clearSelectedBlock();
								hideVirtualKeyboard();
								// Redundant of `useKeyboardVisibility` logic, but improves stability
								setIsKeyboardVisible(false);
							}}
						/>
					</ToolbarGroup>
				)}
			</Toolbar>

			{isBlockInspectorShown && (
				<Popover
					className="block-settings-menu"
					variant="unstyled"
					placement="overlay"
				>
					<>
						<div className="block-settings-menu__header">
							<Button
								className="block-settings-menu__close"
								icon={close}
								onClick={onCloseSettings}
							/>
						</div>
						<BlockInspector />
					</>
				</Popover>
			)}
		</>
	);
};

function hideVirtualKeyboard() {
	if ('virtualKeyboard' in navigator) {
		navigator.virtualKeyboard.hide();
	}
}

export default EditorToolbar;
