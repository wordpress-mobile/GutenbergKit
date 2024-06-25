import { useEffect, useState } from 'react';

// WordPress
import {
    BlockEditorKeyboardShortcuts,
    BlockEditorProvider,
    BlockList,
    BlockTools,
    WritingFlow,
    ObserveTyping,
} from '@wordpress/block-editor';
import { Popover } from '@wordpress/components';
import { registerCoreBlocks } from '@wordpress/block-library';
import { parse, serialize, registerBlockType } from '@wordpress/blocks';

// Default styles that are needed for the editor.
import '@wordpress/components/build-style/style.css';
import '@wordpress/block-editor/build-style/style.css';

// Default styles that are needed for the core blocks.
import '@wordpress/block-library/build-style/style.css';
import '@wordpress/block-library/build-style/editor.css';
import '@wordpress/block-library/build-style/theme.css';

// Registers standard formatting options for RichText.
import '@wordpress/format-library';
import '@wordpress/format-library/build-style/style.css';

// Internal imports
import EditorToolbar from './EditorToolbar';
import { postMessage } from '../misc/Helpers';

// Current editor (assumes can be only one instance).
let editor = {};

function Editor() {
    const [blocks, setBlocks] = useState([]);
    const [registeredBlocks, setRegisteredBlocks] = useState([]);

    function didChangeBlocks(blocks) {
        setBlocks(blocks);

        // TODO: this doesn't include everything
        const isEmpty = blocks.length === 0 || (blocks[0].name == "core/paragraph" && blocks[0].attributes.content.trim() === "");
        postMessage("onBlocksChanged", { isEmpty: isEmpty })
    }

    editor.setContent = (content) => {
        setBlocks(parse(content));
    };

    editor.setInitialContent = (content) => {
        const blocks = parse(content)
        didChangeBlocks(blocks); // TODO: redesign this
        return serialize(blocks); // It's used for tracking changes
    }

    editor.getContent = () => serialize(blocks);

    editor.registerBlocks = (blockTypes) => {
        // TODO: uncomment when the custom picker is ready (blocker: can't insert blocks)
        // setRegisteredBlocks(blockTypes);
        for (const blockType of blockTypes) {
            registerBlockType(blockType.name, blockType);
        }
    }

    // Warning: `useEffect` and functions captured it in can't read the latest useState values,
    // and hence `useRef`.
    useEffect(() => {
        window.editor = editor;
        registerCoreBlocks();
        postMessage("onEditorLoaded");
    }, []);

    const settings = {
        hasFixedToolbar: true
    };

    return (
        <BlockEditorProvider
            value={blocks}
            onInput={didChangeBlocks}
            onChange={didChangeBlocks}
            settings={settings}
        >
            <BlockTools>
                <div className="editor-styles-wrapper">
                    <BlockEditorKeyboardShortcuts.Register />
                    <WritingFlow>
                        <ObserveTyping>
                            <BlockList />
                            <EditorToolbar registeredBlocks={registeredBlocks}/> { /* not sure if optimal placement */}
                        </ObserveTyping>
                    </WritingFlow>
                </div>
            </BlockTools>
            <Popover.Slot />
        </BlockEditorProvider>
    );
}

export default Editor;