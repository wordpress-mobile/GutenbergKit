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

                <Sheet isOpen={isBlockInspectorShown} onClose={() => setBlockInspectorShown(false)}>
                    <Sheet.Container>
                        <Sheet.Header />
                        <Sheet.Content>
                            <BlockInspector />
                        </Sheet.Content>
                    </Sheet.Container>
                    <Sheet.Backdrop />
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