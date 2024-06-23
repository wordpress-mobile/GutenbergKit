import { BlockInspector, BlockToolbar, Inserter } from '@wordpress/block-editor/build/components'
import { useState } from 'react';
import { Sheet } from 'react-modal-sheet';

const EditorToolbar = (props) => {
    const [isBlockInspectorShown, setBlockInspectorShown] = useState(false);

    return (
        <div className='gbkit-editor-toolbar'>
            <Inserter />

            <>
                <button onClick={() => setBlockInspectorShown(true)}>Open sheet</button>

                <Sheet
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
                            <div className="gbkit-sheet-container">
                                <BlockInspector />
                            </div>
                            </Sheet.Scroller>
                        </Sheet.Content>
                    </Sheet.Container>
                </Sheet>
            </>

            {/* <button type="button" onClick={props.onSettingsTapped}>
            ⚙
        </button> */}
            <BlockToolbar />
        </div>
    )
}

export default EditorToolbar