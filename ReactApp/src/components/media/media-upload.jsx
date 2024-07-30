/**
 * WordPress dependencies
 */
import { addFilter } from '@wordpress/hooks';

// eslint-disable-next-line react-refresh/only-export-components
function MediaUpload({ render }) {
	return render({
		open: () => {},
	});
}

addFilter(
	'editor.MediaUpload',
	'core/editor/components/media-upload',
	() => MediaUpload
);
