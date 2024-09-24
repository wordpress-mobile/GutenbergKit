/**
 * WordPress dependencies
 */
import { Notice } from '@wordpress/components';
import { __ } from '@wordpress/i18n';
import { useState, useEffect } from '@wordpress/element';

export default function EditorLoadNotice() {
	const { notice, setNotice } = useEditorLoadNotice();

	const actions = [
		{
			label: 'Retry',
			onClick: () => (window.location.href = 'remote.html'),
			variant: 'primary',
		},
		{
			label: 'Dismiss',
			onClick: () => setNotice(null),
			variant: 'secondary',
		},
	];

	if (!notice) {
		return null;
	}

	return (
		<div className="editor-load-notice">
			<Notice actions={actions} status="warning" isDismissible={false}>
				{notice}
			</Notice>
		</div>
	);
}

function useEditorLoadNotice() {
	const [notice, setNotice] = useState(null);

	useEffect(() => {
		const url = new URL(window.location.href);
		const error = url.searchParams.get('error');

		let message = null;
		switch (error) {
			case REMOTE_EDITOR_LOAD_ERROR:
				message = __(
					"Oops! We couldn't load your site's editor and plugins. Don't worry, you can use the default editor for now."
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

	return { notice, setNotice };
}

const REMOTE_EDITOR_LOAD_ERROR = 'remote_editor_load_error';
