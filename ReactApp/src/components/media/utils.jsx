/**
 * Internal dependencies
 */
import { postMessage } from '../../misc/Helpers';

const noop = () => {};

export function openPicker(id, multiple) {
	postMessage('mediaUpload', {
		callback: `mediaUploadComplete-${id}`,
		multiple,
	});
}

export function mediaUpload({
	additionalData = {},
	allowedTypes,
	filesList,
	maxUploadFileSize,
	onError = noop,
	onFileChange,
}) {}
