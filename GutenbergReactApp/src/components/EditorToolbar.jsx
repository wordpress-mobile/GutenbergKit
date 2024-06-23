import { BlockToolbar, Inserter } from '@wordpress/block-editor/build/components'
import React from 'react'

const EditorToolbar = () => {
  return (
    <div className='gbkit-editor-toolbar'>
        <Inserter />
        <BlockToolbar />
    </div>
  )
}

export default EditorToolbar