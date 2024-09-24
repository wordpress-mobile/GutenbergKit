/**
 * WordPress dependencies
 */
import { Notice } from '@wordpress/components';
import { __ } from '@wordpress/i18n';
import { useState, useEffect } from '@wordpress/element';

export default function EditorLoadNotice() {
	const [notice, setNotice] = useState(null);

	useEffect(() => {
		const url = new URL(window.location.href);
		const error = url.searchParams.get('error');

		let message = null;
		switch (error) {
			case REMOTE_EDITOR_LOAD_ERROR:
				message = __(
					"Oops! We couldn't load your site's editor and plugins. Don't worry, the default editor is here to save the day!"
				);
				break;
			default:
				message = null;
		}

		setNotice(message);
	}, []);

	useEffect(() => {
		if (notice) {
			const timeout = setTimeout(() => {
				setNotice(null);
			}, 20000);
			return () => clearTimeout(timeout);
		}
	}, [notice]);

	const handleDismiss = () => {
		setNotice(null);
	};

	if (!notice) {
		return null;
	}

	return (
		<div className="editor-load-notice">
			<Notice status="warning" onDismiss={handleDismiss}>
				{notice}
			</Notice>
		</div>
	);
}

const REMOTE_EDITOR_LOAD_ERROR = 'remote_editor_load_error';
