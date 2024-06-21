import { useEffect, useState, useRef } from 'react';

import {
    BlockEditorProvider,
    BlockCanvas,
    BlockBreadcrumb,
    BlockInspector
} from "@wordpress/block-editor"
import { registerCoreBlocks } from '@wordpress/block-library';
import { parse, createBlock, serialize } from '@wordpress/blocks';

import useWindowDimensions from '../misc/WindowsDimenstionsHook';

import '@wordpress/components/build-style/style.css';
import '@wordpress/block-editor/build-style/style.css';
import '@wordpress/block-library/build-style/style.css';
import '@wordpress/block-library/build-style/editor.css';
import '@wordpress/block-library/build-style/theme.css';

function postMessage(message) {
    if (window.webkit) {
        window.webkit.messageHandlers.editorDelegate.postMessage(message);
    };
};

function Editor() {
    const [blocks, updateBlocks] = useState([]);
    const { height, width } = useWindowDimensions();
    const [isBlockSettingsInspectorHidden, setBlockSettingsInspectorHidden] = useState(false);
    const messageCallback = useRef();

    function onInput(blocks) {
        updateBlocks(blocks);
    };

    function onChange(blocks) {
        updateBlocks(blocks);
    };

    function setContent(content) {
        const convertParsedBlocksToBlockInstances = (parsedBlocks) => {
            return parsedBlocks.map(parsedBlock => {
                const { name, attributes, innerBlocks } = parsedBlock;
                const convertedInnerBlocks = convertParsedBlocksToBlockInstances(innerBlocks);
                return createBlock(name, attributes, convertedInnerBlocks);
            });
        };
        const parsedBlocks = parse(content); // Returns ParsedBlock[]
        const blockInstances = convertParsedBlocksToBlockInstances(parsedBlocks); // Returns BlockInstance[]
        updateBlocks(blockInstances);
    };

    function getContent(requestID) {
        postMessage({ 
            message: "onContentProvided", 
            body: { content: btoa(serialize(blocks)), requestID: requestID }
        });
    }

    // Handles messages receives from the native app.
    messageCallback.current = (event) => {
        const message = event.data;
        switch (message.event) {
            case "toggleBlockSettingsInspector":
                setBlockSettingsInspectorHidden(value => !value);
                break;
            case "setContent":
                setContent(message.content);
                break;
            case "getContent":
                getContent(message.requestID);
                break;
            default:
                break;
        }
    };

    // Warning: `useEffect` and functions captured it in can't read the latest useState values,
    // and hence `useRef`.
    useEffect(() => {
        registerCoreBlocks();

        const handleMessage = (event) => messageCallback.current(event);
        window.addEventListener('message', handleMessage);

        postMessage({ message: "onEditorLoaded" });

        // Clean up the event listener
        return () => {
            window.removeEventListener('message', handleMessage);
        };
    }, []);

    // Injects CSS styles in the canvas iframe.
    const style = `
    body { 
        padding: 12px; 
        font-family: -apple-system; 
        line-height: 1.55;
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

    const settings = {
    };

    return (
        <BlockEditorProvider
            value={blocks}
            onInput={onInput}
            onChange={onChange}
            settings={settings}
        >
            <div className='gbkit-main-container'>
                <div className='gbkit-canvas-container' style={{width: `${width}px`}}>
                    <BlockCanvas height={`${height}px`} styles={styles} />
                    {/* <BlockBreadcrumb /> */}
                    {/* <div className='gbkit-debug-toolbar'>
                        <button type="button" onClick={() => window.postMessage({ event: "toggleBlockSettingsInspector" })}>
                            Toogle Block Settings
                        </button>
                        <button type="button" onClick={() => window.postMessage({ event: "getContent", requestID: "1" })}>
                            Send Content
                        </button>
                    </div> */}
                </div>
                {/* <div className='gbkit-spacer'></div>
                {!isBlockSettingsInspectorHidden &&
                    <div className="block-inspector-siderbar">
                        <BlockInspector />
                    </div>} */}
            </div>
        </BlockEditorProvider>
    );
}

export default Editor;