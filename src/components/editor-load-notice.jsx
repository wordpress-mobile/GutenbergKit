/**
 * WordPress dependencies
 */
import { Notice } from '@wordpress/components';
import { __ } from '@wordpress/i18n';
import { useState, useEffect } from '@wordpress/element';

const pluginLoadFailedNotice = __(
	'Loading plugins failed, using default editor configuration.',
	'gutenberg-kit'
);

/**
 * Displays a notice with actions to retry or dismiss.
 *
 * @param {Object}  props                  Component props.
 * @param {string}  props.className        Additional class names to apply.
 * @param {boolean} props.pluginLoadFailed Whether plugin loading failed.
 *
 * @return {?JSX.Element} The rendered component or null if no notice is present.
 */
export default function EditorLoadNotice( { className, pluginLoadFailed } ) {
	const { notice, clearNotice } = useEditorLoadNotice(
		pluginLoadFailed ? pluginLoadFailedNotice : null
	);

	if ( ! notice ) {
		return null;
	}

	return (
		<div className={ className }>
			<Notice status="warning" onRemove={ clearNotice }>
				{ notice }
			</Notice>
		</div>
	);
}

/**
 * Conditionally and temporarily sets a notice message.
 *
 * @param {string|null} initialNotice The initial notice message.
 *
 * @return {{notice:string|null, clearNotice:()=>void}} The notice message and a function to clear it.
 */
function useEditorLoadNotice( initialNotice ) {
	const [ notice, setNotice ] = useState( initialNotice );

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
