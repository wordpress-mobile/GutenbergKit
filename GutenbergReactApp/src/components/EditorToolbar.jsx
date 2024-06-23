import { BlockInspector, BlockToolbar, Inserter } from '@wordpress/block-editor/build/components'
import { useState } from 'react';
import { Sheet } from 'react-modal-sheet';
import { postMessage } from '../misc/Helpers';

const EditorToolbar = () => {
    const [isBlockInspectorShown, setBlockInspectorShown] = useState(false);

    function _setBlockInspectorShown(isShown) {
        postMessage("onSheetVisibilityUpdated", { isShown: isShown });
        setBlockInspectorShown(isShown);
    }

    return (
        <div className='gbkit-editor-toolbar'>
            <Inserter />

            <>
                <button onClick={() => _setBlockInspectorShown(true)}>Settings</button>

                <Sheet
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
                            <div className="gbkit-sheet-container">
                                <BlockInspector />
                            </div>
                            </Sheet.Scroller>
                        </Sheet.Content>
                    </Sheet.Container>
                    <Sheet.Backdrop />
                </Sheet>
            </>

            <BlockToolbar />
        </div>
    )
}

export default EditorToolbar