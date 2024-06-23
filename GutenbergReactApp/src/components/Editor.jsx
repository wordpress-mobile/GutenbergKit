/* React */
import { useEffect, useState } from 'react';

/* WordPress */
import {
    BlockEditorKeyboardShortcuts,
    BlockEditorProvider,
    BlockList,
    BlockTools,
    WritingFlow,
    ObserveTyping,
} from '@wordpress/block-editor';
import { Popover, SlotFillProvider } from '@wordpress/components';
import { ShortcutProvider } from '@wordpress/keyboard-shortcuts';
import { registerCoreBlocks } from '@wordpress/block-library';
import { serialize } from '@wordpress/blocks';

import '@wordpress/components/build-style/style.css';
import '@wordpress/block-editor/build-style/style.css';
import '@wordpress/block-library/build-style/style.css';
import '@wordpress/block-library/build-style/editor.css';
import '@wordpress/block-library/build-style/theme.css';

/* Internal */

import EditorToolbar from './EditorToolbar';
import { instantiateBlocksFromContent } from '../misc/Helpers';

// Current editor (assumes can be only one instance).
let editor = {};

function Editor() {
    const [blocks, updateBlocks] = useState([]);

    function onInput(blocks) {
        updateBlocks(blocks);
    };

    function onChange(blocks) {
        updateBlocks(blocks);

        // TODO: this doesn't include everything
        const isEmpty = blocks.length === 0 || (blocks[0].name == "core/paragraph" && blocks[0].attributes.content.trim() === "");
        postMessage({ message: "onBlocksChanged", body: { isEmpty: isEmpty } });
    };

    editor.setContent = (content) => {
        updateBlocks(instantiateBlocksFromContent(content));
    };

    editor.setInitialContent = (content) => {
        const blocks = instantiateBlocksFromContent(content);
        onChange(blocks); // TODO: redesign this
        return serialize(blocks);
    }

    editor.getContent = () => serialize(blocks);

    // Warning: `useEffect` and functions captured it in can't read the latest useState values,
    // and hence `useRef`.
    useEffect(() => {
        window.editor = editor;
        registerCoreBlocks();
        postMessage({ message: "onEditorLoaded" });
    }, []);

    const settings = {
        hasFixedToolbar: true
    };

    return (
        <ShortcutProvider>
            <SlotFillProvider>
                <BlockEditorProvider
                    value={blocks}
                    onInput={onInput}
                    onChange={onChange}
                    settings={settings}
                >
                    <BlockTools className="gbkit-canvas-container">
                        <div className="editor-styles-wrapper">
                            <BlockEditorKeyboardShortcuts.Register />
                            <WritingFlow>
                                <ObserveTyping>
                                    <BlockList />
                                </ObserveTyping>
                            </WritingFlow>
                        </div>
                    </BlockTools>
                    <Popover.Slot />
                    <EditorToolbar />
                </BlockEditorProvider>
            </SlotFillProvider>
        </ShortcutProvider>
    );
}

function postMessage(message) {
    if (window.webkit) {
        window.webkit.messageHandlers.editorDelegate.postMessage(message);
    };
};

export default Editor;