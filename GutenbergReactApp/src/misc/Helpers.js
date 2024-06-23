import { parse, createBlock } from '@wordpress/blocks';

// Returns BlockInstance[]
export function instantiateBlocksFromContent(content) {
    const convertParsedBlocksToBlockInstances = (parsedBlocks) => {
        return parsedBlocks.map(parsedBlock => {
            const { name, attributes, innerBlocks } = parsedBlock;
            const convertedInnerBlocks = convertParsedBlocksToBlockInstances(innerBlocks);
            return createBlock(name, attributes, convertedInnerBlocks);
        });
    };
    const parsedBlocks = parse(content); // Returns ParsedBlock[]
    return convertParsedBlocksToBlockInstances(parsedBlocks);
}

export function postMessage(message, parameters = {}) {
    if (window.webkit) {
        const value = { message: message, body: parameters }
        window.webkit.messageHandlers.editorDelegate.postMessage(value);
    };
};