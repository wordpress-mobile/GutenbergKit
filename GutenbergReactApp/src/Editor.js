/**
 * WordPress dependencies
 */
import { useEffect, useState } from 'react';
import {
    BlockCanvas,
    BlockEditorProvider,
    BlockList,
    BlockListBlock,
    BlockEdit
} from '@wordpress/block-editor';
import { registerCoreBlocks } from '@wordpress/block-library';

import '@wordpress/components/build-style/style.css';
import '@wordpress/block-editor/build-style/style.css';
import '@wordpress/block-library/build-style/style.css';
import '@wordpress/block-library/build-style/editor.css';
import '@wordpress/block-library/build-style/theme.css';

import './Editor.css';

function postMessage(message) {
    if (window.webkit) {
        window.webkit.messageHandlers.appMessageHandler.postMessage(message);
    };
};

function Editor() {
	const [ blocks, updateBlocks ] = useState( [] );

	useEffect( () => {
		registerCoreBlocks();
	}, [] );

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

	return (
        <BlockEditorProvider 
            value={ blocks }
            onInput={onInput}
            onChange={onChange}
        >
            <BlockCanvas height="500px"/>
        </BlockEditorProvider>
	);
}

export default Editor;