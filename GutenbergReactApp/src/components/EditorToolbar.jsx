import { BlockInspector, BlockToolbar, Inserter } from '@wordpress/block-editor';
import { Popover } from '@wordpress/components';
import { useState } from 'react';
// import { Sheet } from 'react-modal-sheet';
import { postMessage } from '../misc/Helpers';

const EditorToolbar = (props) => {
    const [isBlockInspectorShown, setBlockInspectorShown] = useState(false);

    function _setBlockInspectorShown(isShown) {
        // FIXME: this is the iteration that was using Sheet from 'react-modal-sheet'
        // postMessage("onSheetVisibilityUpdated", { isShown: isShown });
        setBlockInspectorShown(isShown);
    }

    let addBlockButton;
    if (props.registeredBlocks.length === 0) {
        // TODO: use the native inserter
        addBlockButton = <Inserter />;
    } else {
        addBlockButton = <button onClick={() => postMessage("showBlockPicker")}>+</button>
    }

    return (
        <div className='gbkit-editor-toolbar'>
            <div className="gbkit-editor-toolbar_toolbar-group">
                {addBlockButton}

                <button onClick={() => _setBlockInspectorShown(true)} className="components-button gbkit-editor-toolbar_settings_icon "></button>
            </div>

            {isBlockInspectorShown && <Popover
                expandOnMobile={true}
                focusOnMount="container"
                headerTitle="Block Settings"
                onClose={() => { _setBlockInspectorShown(false) }}
            >
                <BlockInspector />
            </Popover>}

            {/* // FIXME: this is the iteration that was using Sheet from 'react-modal-sheet' */}
            {/* <Sheet
                isOpen={isBlockInspectorShown}
                onClose={() => _setBlockInspectorShown(false)}
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
    )
}

export default EditorToolbar