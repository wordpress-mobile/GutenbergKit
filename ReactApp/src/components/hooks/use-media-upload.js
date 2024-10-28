/**
 * WordPress dependencies
 */
import { addFilter, removeFilter } from '@wordpress/hooks';
import { useCallback, useEffect } from '@wordpress/element';
import { openMediaLibrary } from '../../misc/Helpers';

export function useMediaUpload() {
	useEffect(() => {
		addFilter('editor.MediaUpload', 'GutenbergKit', () => MediaUpload);

		return () => {
			removeFilter('editor.MediaUpload', 'GutenbergKit');
		};
	}, []);
}

function MediaUpload({ render, ...config }) {
	const { open } = useNativeMediaLibrary(config);

	return render({ open });
}

function useNativeMediaLibrary({ onSelect, ...config }) {
	useEffect(() => {
		window.editor.onMediaLibrarySelect = (attachment) => {
			onSelect(config.multiple ? attachment : attachment[0]);
		};

		return () => {
			window.editor.onMediaLibrarySelect = () => {};
		};
	}, [onSelect, config.multiple]);

	const open = useCallback(() => openMediaLibrary(config), [config]);

	return { open };
}
