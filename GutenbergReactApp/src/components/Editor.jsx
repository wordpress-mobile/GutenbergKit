import { useEffect, useState } from 'react';

import { BlockEditorProvider, BlockCanvas } from "@wordpress/block-editor"
import { registerCoreBlocks } from '@wordpress/block-library';

import '@wordpress/components/build-style/style.css';
import '@wordpress/block-editor/build-style/style.css';
import '@wordpress/block-library/build-style/style.css';
import '@wordpress/block-library/build-style/editor.css';
import '@wordpress/block-library/build-style/theme.css';

function postMessage(message) {
    if (window.webkit) {
        window.webkit.messageHandlers.appMessageHandler.postMessage(message);
    };
};

function Editor() {
    const [blocks, updateBlocks] = useState([]);

    useEffect(() => {
        registerCoreBlocks();
    }, []);

    function onInput(blocks) {
        updateBlocks(blocks);
    };

    function onChange(blocks) {
        updateBlocks(blocks);
        postMessage({
            "message": "onBlocksChanged",
            "body": blocks
        });
        console.log(blocks);
    };

    // The problem with the editor canvas is that it gets embedded in an iframe
    // so there is no way to style it directly using CSS included in the project itself.
    const styles = [
        { css: `body { padding: 12px; font-family: -apple-system; } .rich-text:focus { outline: none; }` },
    ];

    const settings = {};

    return (
        <BlockEditorProvider
            value={blocks}
            onInput={onInput}
            onChange={onChange}
            settings={settings}
        >
            <BlockCanvas height="500px" styles={styles} />
        </BlockEditorProvider>
    );
}

export default Editor;