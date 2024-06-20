import { useEffect, useState } from 'react';

import {
    BlockEditorProvider,
    BlockCanvas,
    BlockBreadcrumb,
    BlockInspector
} from "@wordpress/block-editor"
import { registerCoreBlocks } from '@wordpress/block-library';

import useWindowDimensions from '../misc/WindowsDimenstionsHook';

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
    const {height, width} = useWindowDimensions();

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

    const style = `
    body { 
        padding: 12px; 
        font-family: -apple-system; 
    }
    .rich-text:focus { 
        outline: none; 
    }
    `

    // The problem with the editor canvas is that it gets embedded in an iframe
    // so there is no way to style it directly using CSS included in the project itself.
    const styles = [
        { css: style },
    ];

    const settings = {};

    return (
        <BlockEditorProvider
            value={blocks}
            onInput={onInput}
            onChange={onChange}
            settings={settings}
        >
            <BlockCanvas height={`${height - 44}px`} styles={styles} />
            <div className="block-inspector-siderbar">
                <BlockInspector />
            </div>
            <BlockBreadcrumb />
        </BlockEditorProvider>
    );
}

export default Editor;