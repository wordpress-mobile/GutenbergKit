/**
 * External dependencies
 */
import { v4 as uuid } from 'uuid';

/**
 * WordPress dependencies
 */
import { addFilter } from '@wordpress/hooks';
import { useCallback, useEffect } from '@wordpress/element';
import { openMediaLibrary } from '../../misc/Helpers';

export function useMediaUpload() {
	useEffect(() => {
		addFilter('editor.MediaUpload', 'GutenbergKit', () => MediaUpload);
	}, []);
}

function MediaUpload({ render, ...config }) {
	const { open } = useNativeMediaLibrary(config);

	return render({ open });
}

function useNativeMediaLibrary({ onSelect, ...config }) {
	let id;

	useEffect(() => {
		id = uuid();
		window.editor.onMediaLibrarySelect =
			window.editor.onMediaLibrarySelect || {};
		window.editor.onMediaLibrarySelect[id] = (attachment) => {
			onSelect(config.multiple ? attachment : attachment[0]);
		};

		return () => {
			delete window.editor.onMediaLibrarySelect[id];
		};
	}, [onSelect, config.multiple]);

	const open = useCallback(() => openMediaLibrary(id, config), [id, config]);

	return { open };
}
