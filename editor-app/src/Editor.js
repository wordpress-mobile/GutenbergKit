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

	return (
        <BlockEditorProvider bodyPlaceholder="Test">
            <BlockCanvas/>
        </BlockEditorProvider>
	);
}

export default Editor;