/**
 * WordPress dependencies
 */
import { useEffect, useState } from 'react';
import {
    BlockCanvas,
    BlockEditorProvider,
    BlockList,
} from '@wordpress/block-editor';
import { registerCoreBlocks } from '@wordpress/block-library';

import '@wordpress/components/build-style/style.css';
import '@wordpress/block-editor/build-style/style.css';
import '@wordpress/block-library/build-style/style.css';
import '@wordpress/block-library/build-style/editor.css';
import '@wordpress/block-library/build-style/theme.css';

import './Editor.css';

/**
 * Internal dependencies
 */

function Editor() {
	const [ blocks, updateBlocks ] = useState( [] );

	useEffect( () => {
		registerCoreBlocks();
	}, [] );

    function onInput(blocks) {
        console.log("onInput");
        updateBlocks(blocks);
        // TODO: reuse this code
        // if (window.webkit.messageHandlers) {
        //     window.webkit.messageHandlers.appMessageHandler.postMessage(blocks);
        // };
        // console.log(blocks);
    };

    function onChange(blocks) {
        console.log("onChange");
        updateBlocks(blocks);
        // TODO: reuse this code
        if (window.webkit) {
            window.webkit.messageHandlers.appMessageHandler.postMessage(blocks);
        };
        console.log(blocks);
    };

	return (
        <BlockEditorProvider 
            value={ blocks }
            onInput={onInput}
            onChange={onChange}
        >
            <BlockCanvas/>
        </BlockEditorProvider>
	);
}

export default Editor;