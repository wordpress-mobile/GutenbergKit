/**
 * WordPress dependencies
 */
import { addFilter } from '@wordpress/hooks';
import { useEffect } from '@wordpress/element';
import { openMediaLibrary } from '../../misc/Helpers';

export function useMediaUpload() {
	useEffect(() => {
		addFilter('editor.MediaUpload', 'GutenbergKit', () => MediaUpload);
	}, []);
}

function MediaUpload({ onSelect, render, ...config }) {
	const open = () => openMediaLibrary(config);

	useEffect(() => {
		window.editor.onMediaLibrarySelect = (...args) => {
			console.log('>>> onMediaLibrarySelect', args);
			onSelect(...args);
		};
	}, [onSelect]);

	return render({ open });
}
