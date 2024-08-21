/**
 * WordPress dependencies
 */
import { useState } from '@wordpress/element';
import {
	BlockInspector,
	BlockToolbar,
	Inserter,
} from '@wordpress/block-editor';
import { Popover } from '@wordpress/components';
// import { Sheet } from 'react-modal-sheet';
import { showBlockPicker } from '../misc/Helpers';

const EditorToolbar = (props) => {
	const [isBlockInspectorShown, setBlockInspectorShown] = useState(false);

	let addBlockButton;
	if (props.registeredBlocks.length === 0) {
		// TODO: use the native inserter
		addBlockButton = <Inserter />;
	} else {
		addBlockButton = <button onClick={() => showBlockPicker()}>+</button>;
	}

	return (
		<div className="gbkit gbkit-editor-toolbar">
			<div className="gbkit-editor-toolbar_toolbar-group">
				{addBlockButton}

				<button
					onClick={() => setBlockInspectorShown(true)}
					className="components-button gbkit-editor-toolbar_settings_icon "
				></button>
			</div>

			{isBlockInspectorShown && (
				<Popover
					expandOnMobile={true}
					focusOnMount="container"
					headerTitle="Block Settings"
					onClose={() => {
						setBlockInspectorShown(false);
					}}
				>
					<BlockInspector />
				</Popover>
			)}

			{/* // FIXME: this is the iteration that was using Sheet from 'react-modal-sheet' */}
			{/* <Sheet
                isOpen={isBlockInspectorShown}
                onClose={() => setBlockInspectorShown(false)}
                snapPoints={[window.innerHeight - 20, 400, 0]}
                initialSnap={1}
                tweenConfig={{ ease: 'anticipate', duration: 0.5 }}
            >
                <Sheet.Container>
                    <Sheet.Header />
                    <Sheet.Content>
                        <Sheet.Scroller>
                            
                                <BlockInspector />
                            </div>
                        </Sheet.Scroller>
                    </Sheet.Content>
                </Sheet.Container>
                <Sheet.Backdrop />
            </Sheet> */}

			<BlockToolbar />
		</div>
	);
};

export default EditorToolbar;
