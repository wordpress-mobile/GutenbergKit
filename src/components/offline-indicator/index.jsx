/**
 * WordPress dependencies
 */
import { speak } from '@wordpress/a11y';
import { Icon } from '@wordpress/components';
import { useState, useEffect } from '@wordpress/element';
import { __ } from '@wordpress/i18n';
import { offline } from '@wordpress/icons';

/**
 * Internal dependencies
 */
import { getGBKit } from '../../utils/bridge';
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

	useEffect( () => {
		if ( ! isConnected ) {
			speak(
				__(
					'Network connection lost, working offline',
					'gutenberg-kit'
				),
				'assertive'
			);
		}
	}, [ isConnected ] );

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
 * Tracks network connectivity using browser online/offline events verified by
 * a real HTTP probe.
 *
 * The `offline` event is treated as immediately authoritative. The `online`
 * event triggers a probe to confirm actual connectivity before clearing the
 * indicator, guarding against false positives from `navigator.onLine`.
 *
 * Initial state reads `navigator.onLine` but only trusts `false` — a definitive
 * signal the browser has no network interface. A `true` value is not trusted on
 * its own; Chrome is known to misreport it. If the browser reports online at
 * mount, a probe runs immediately to verify before committing to that state.
 *
 * @return {{ isConnected: boolean }} Whether the device is currently connected.
 */
function useNetworkConnectivity() {
	const [ isConnected, setIsConnected ] = useState( navigator.onLine );

	useEffect( () => {
		const abortController = new AbortController();

		// If the browser reports online at mount, probe immediately to catch
		// Chrome incorrectly reporting navigator.onLine as true.
		if ( navigator.onLine ) {
			probeConnectivity().then( ( connected ) => {
				if ( ! abortController.signal.aborted ) {
					setIsConnected( connected );
				}
			} );
		}

		const handleOnline = async () => {
			const connected = await probeConnectivity();
			if ( ! abortController.signal.aborted ) {
				setIsConnected( connected );
			}
		};
		const handleOffline = () => setIsConnected( false );

		window.addEventListener( 'online', handleOnline );
		window.addEventListener( 'offline', handleOffline );

		return () => {
			abortController.abort();
			window.removeEventListener( 'online', handleOnline );
			window.removeEventListener( 'offline', handleOffline );
		};
	}, [] );

	return { isConnected };
}

/**
 * Probes real internet connectivity by making a lightweight HEAD request.
 *
 * `navigator.onLine` and the browser `online` event are unreliable — they only
 * confirm a network interface is active, not that the internet is reachable.
 * This probe verifies actual connectivity before reporting online status.
 *
 * @return {Promise<boolean>} Whether the probe request succeeded.
 */
async function probeConnectivity() {
	try {
		await window.fetch( getConnectivityProbeUrl(), {
			method: 'HEAD',
			cache: 'no-store',
			signal: AbortSignal.timeout( 5000 ),
		} );
		return true;
	} catch {
		return false;
	}
}

/**
 * Returns a URL suitable for probing real internet connectivity.
 *
 * Prefers the site API root (already used by the editor, same origin, no CORS
 * concerns) so that the probe reflects whether the WordPress API specifically
 * is reachable. Falls back to `/favicon.ico` for local dev environments where
 * no GBKit config is available.
 *
 * @return {string} The probe URL.
 */
function getConnectivityProbeUrl() {
	const { siteApiRoot } = getGBKit();
	return siteApiRoot || '/favicon.ico';
}
