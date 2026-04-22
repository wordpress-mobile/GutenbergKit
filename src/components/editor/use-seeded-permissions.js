/**
 * WordPress dependencies
 */
import { useEffect } from '@wordpress/element';
import { dispatch, select } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';

/**
 * Internal dependencies
 */
import { getGBKit } from '../../utils/bridge';

const ATTACHMENT_RESOURCE = { kind: 'postType', name: 'attachment' };
const RESOURCE_ACTIONS = [ 'create', 'read', 'update', 'delete' ];

/**
 * Preseeds `canUser` results in the `@wordpress/core-data` store from
 * host-supplied capabilities, bypassing the REST `OPTIONS` resolver.
 *
 * Cross-origin editor hosts cannot read the `Allow` response header unless
 * the server explicitly exposes it via `Access-Control-Expose-Headers`.
 * Since `@wordpress/core-data` 7.42.0, a missing `Allow` header causes
 * `canUser` to return `false`, which hides the upload button in
 * `MediaPlaceholder`. Seeding the store with the host's authoritative
 * capability information avoids this inference path entirely.
 *
 * The host may supply `userCapabilities` via `window.GBKit`, e.g.:
 *   window.GBKit = {
 *     ...,
 *     userCapabilities: { uploadFiles: true },
 *   };
 *
 * If `userCapabilities` is absent, the default `canUser` resolver runs
 * (matching existing behavior).
 *
 * @return {void}
 */
export function useSeededPermissions() {
	useEffect( () => {
		const { userCapabilities } = getGBKit();
		if ( ! userCapabilities ) {
			return;
		}

		const storeSelect = select( coreStore );
		// Avoid clobbering a resolution already in flight.
		if (
			storeSelect.hasStartedResolution( 'canUser', [
				'create',
				ATTACHMENT_RESOURCE,
			] )
		) {
			return;
		}

		const permissions = {};
		const resolutions = [];

		if ( userCapabilities.uploadFiles === true ) {
			for ( const action of RESOURCE_ACTIONS ) {
				permissions[ `${ action }/postType/attachment` ] = true;
				resolutions.push( [ action, ATTACHMENT_RESOURCE ] );
			}
		}

		if ( resolutions.length === 0 ) {
			return;
		}

		dispatch( coreStore ).receiveUserPermissions( permissions );
		dispatch( coreStore ).finishResolutions( 'canUser', resolutions );
	}, [] );
}
