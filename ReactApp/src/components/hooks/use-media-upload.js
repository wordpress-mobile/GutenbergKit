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
		// TODO: This global is likely causing issue with multiple instances in the
		// editor causing unexpected media replacements, namely in Gallery blocks.
		window.editor.onMediaLibrarySelect = (attachment) => {
			console.log('>>> onMediaLibrarySelect', attachment);
			onSelect(config.multiple ? attachment : attachment[0]);
		};
	}, [onSelect, config.multiple]);

	return render({ open });
}
