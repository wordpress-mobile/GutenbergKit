/**
 * WordPress dependencies
 */
import { Notice } from '@wordpress/components';
import { __ } from '@wordpress/i18n';
import { useState, useEffect } from '@wordpress/element';

/**
 * Displays a notice with actions to retry or dismiss.
 *
 * @param {Object} props           Component props.
 * @param {string} props.className Additional class names to apply.
 *
 * @return {?JSX.Element} The rendered component or null if no notice is present.
 */
export default function EditorLoadNotice( { className } ) {
	const { notice, clearNotice } = useEditorLoadNotice();

	const actions = [
		{
			label: __( 'Retry', 'gutenberg-kit' ),
			onClick: () => ( window.location.href = 'remote.html' ),
			variant: 'primary',
		},
		{
			label: __( 'Dismiss', 'gutenberg-kit' ),
			onClick: clearNotice,
			variant: 'secondary',
		},
	];

	if ( ! notice ) {
		return null;
	}

	return (
		<div className={ className }>
			<Notice
				actions={ actions }
				status="warning"
				isDismissible={ false }
			>
				{ notice }
			</Notice>
		</div>
	);
}

/**
 * Conditionally and temporarily sets a notice message based on the URL.
 *
 * @return {{notice:string, clearNotice:()=>void}} The notice message and a function to clear it.
 */
function useEditorLoadNotice() {
	const [ notice, setNotice ] = useState( null );

	useEffect( () => {
		const url = new URL( window.location.href );
		const error = url.searchParams.get( 'error' );

		let message = null;
		switch ( error ) {
			case REMOTE_EDITOR_LOAD_ERROR:
				message = __(
					"Oops! We couldn't load your site's editor and plugins. Don't worry, you can use the default editor for now.",
					'gutenberg-kit'
				);
				break;
			case GBKIT_GLOBAL_UNAVAILABLE:
				message = __(
					"Oops! Configuration for your site editor was unavailable. Don't worry, you can use the default editor for now.",
					'gutenberg-kit'
				);
				break;
			default:
				message = null;
		}

		setNotice( message );
	}, [] );

	useEffect( () => {
		if ( notice ) {
			const timeout = setTimeout( () => {
				setNotice( null );
			}, 20000 );
			return () => clearTimeout( timeout );
		}
	}, [ notice ] );

	return { notice, clearNotice: () => setNotice( null ) };
}

const REMOTE_EDITOR_LOAD_ERROR = 'remote_editor_load_error';
const GBKIT_GLOBAL_UNAVAILABLE = 'gbkit_global_unavailable';
