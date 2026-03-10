/**
 * WordPress dependencies
 */
import { speak } from '@wordpress/a11y';
import { Icon } from '@wordpress/components';
import { useState, useEffect, useRef } from '@wordpress/element';
import { __ } from '@wordpress/i18n';
import { offline } from '@wordpress/icons';

/**
 * Internal dependencies
 */
import './style.scss';

/**
 * Displays a thin status bar when the device is offline.
 *
 * The indicator automatically shows/hides based on the browser's online/offline
 * events — no manual dismiss needed.
 *
 * @return {?Element} The rendered component or null when online.
 */
export default function OfflineIndicator() {
	const { isConnected } = useNetworkConnectivity();

	if ( isConnected ) {
		return null;
	}

	return (
		<div className="gutenberg-kit-offline-indicator">
			<Icon icon={ offline } size={ 18 } />
			{ __( 'Working Offline', 'gutenberg-kit' ) }
		</div>
	);
}

/**
 * Tracks browser network connectivity via online/offline events.
 *
 * @return {{ isConnected: boolean }} Whether the device is currently online.
 */
function useNetworkConnectivity() {
	const [ isConnected, setIsConnected ] = useState( navigator.onLine );
	const hasInitialized = useRef( false );

	useEffect( () => {
		const handleOnline = () => setIsConnected( true );
		const handleOffline = () => {
			setIsConnected( false );
			speak(
				__( 'Network connection lost', 'gutenberg-kit' ),
				'assertive'
			);
		};

		if ( ! hasInitialized.current ) {
			hasInitialized.current = true;
			if ( ! navigator.onLine ) {
				handleOffline();
			}
		}

		window.addEventListener( 'online', handleOnline );
		window.addEventListener( 'offline', handleOffline );

		return () => {
			window.removeEventListener( 'online', handleOnline );
			window.removeEventListener( 'offline', handleOffline );
		};
	}, [] );

	return { isConnected };
}
