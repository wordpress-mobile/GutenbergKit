/**
 * WordPress dependencies
 */
import { useEntityBlockEditor } from '@wordpress/core-data';
import { privateApis as blockEditorPrivateApis } from '@wordpress/block-editor';
import { useSelect } from '@wordpress/data';
import { store as editorStore } from '@wordpress/editor';
import { useRef } from '@wordpress/element';

/**
 * Internal dependencies
 */
import VisualEditor from '../visual-editor';
import './style.scss';
import { useSyncHistoryControls } from './use-sync-history-controls';
import { useHostBridge } from './use-host-bridge';
import { useHostExceptionLogging } from './use-host-exception-logging';
import { useEditorSetup } from './use-editor-setup';
import { useMediaUpload } from './use-media-upload';
import { useGBKitSettings } from './use-gbkit-settings';
import { unlock } from '../../lock-unlock';
import TextEditor from '../text-editor';

/**
 * @typedef {import('../utils/bridge').Post} Post
 */

const { ExperimentalBlockEditorProvider: BlockEditorProvider } = unlock(
	blockEditorPrivateApis
);

/**
 * Entry component rendering the editor and surrounding UI.
 *
 * @param {Object}                               props           Component props.
 * @param {Post}                                 props.post      Post object containing post details.
 * @param {boolean}                              props.hideTitle Whether to hide the title input.
 * @param {import('@wordpress/element').Element} props.children  The children to render in the editor.
 *
 * @return {JSX.Element} The rendered App component.
 */
export default function Editor( { post, children, hideTitle } ) {
	const editorRef = useRef( null );
	useHostBridge( post, editorRef );
	useSyncHistoryControls();
	useHostExceptionLogging();
	useEditorSetup( post );
	useMediaUpload();

	const [ postBlocks, onInput, onChange ] = useEntityBlockEditor(
		'postType',
		post.type,
		{ id: post.id }
	);

	const settings = useGBKitSettings( post );

	const { isReady, mode, isRichEditingEnabled } = useSelect( ( select ) => {
		const { __unstableIsEditorReady, getEditorSettings, getEditorMode } =
			select( editorStore );
		const editorSettings = getEditorSettings();

		return {
			// TODO(Perf): The `__unstableIsEditorReady` selector is insufficient as
			// it does not account for post type loading, which is first referenced
			// within the post title component render. This results in the post title
			// popping in after the editor mounted. The web editor does not experience
			// this issue because the post type is loaded for "mode" selection before
			// the editor is mounted.
			isReady: __unstableIsEditorReady(),
			mode: getEditorMode(),
			isRichEditingEnabled: editorSettings.richEditingEnabled,
		};
	}, [] );

	if ( ! isReady ) {
		return null;
	}

	return (
		<div className="gutenberg-kit-editor" ref={ editorRef }>
			<BlockEditorProvider
				value={ postBlocks }
				onInput={ onInput }
				onChange={ onChange }
				settings={ settings }
				useSubRegistry={ false }
			>
				{ mode === 'visual' && isRichEditingEnabled && (
					<VisualEditor hideTitle={ hideTitle } />
				) }

				{ ( mode === 'text' || ! isRichEditingEnabled ) && (
					<TextEditor
						// We should auto-focus the canvas (title) on load.
						// eslint-disable-next-line jsx-a11y/no-autofocus
						autoFocus={ true }
						hideTitle={ hideTitle }
					/>
				) }

				{ children }
			</BlockEditorProvider>
		</div>
	);
}
