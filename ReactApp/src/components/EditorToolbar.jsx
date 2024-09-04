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
import { useSelect } from '@wordpress/data';
import { Button, Popover, ToolbarButton } from '@wordpress/components';
import { __ } from '@wordpress/i18n';
import { close, cog } from '@wordpress/icons';

const EditorToolbar = () => {
	const [isBlockInspectorShown, setBlockInspectorShown] = useState(false);
	const { isSelected } = useSelect((select) => {
		const { getSelectedBlockClientId } = select(blockEditorStore);
		const selectedBlockClientId = getSelectedBlockClientId();
		return {
			isSelected: selectedBlockClientId !== null,
		};
	});

	function openSettings() {
		setBlockInspectorShown(true);
	}

	function onCloseSettings() {
		setBlockInspectorShown(false);
	}

	return (
		<>
			<div className="gbkit gbkit-editor-toolbar">
				<Inserter />

				{isSelected && (
					<div className="gbkit-editor-toolbar_toolbar-group">
						<ToolbarButton
							title={__('Open Settings')}
							icon={cog}
							onClick={openSettings}
							className="gbkit-editor-toolbar_settings_icon"
						></ToolbarButton>
					</div>
				)}

				<BlockToolbar />
			</div>

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

export default EditorToolbar;
