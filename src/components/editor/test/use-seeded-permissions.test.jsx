/**
 * External dependencies
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook } from '@testing-library/react';

/**
 * Internal dependencies
 */
import { useSeededPermissions } from '../use-seeded-permissions';

const mockReceiveUserPermissions = vi.fn();
const mockFinishResolutions = vi.fn();
const mockHasStartedResolution = vi.fn();

vi.mock( '@wordpress/data', () => ( {
	dispatch: () => ( {
		receiveUserPermissions: mockReceiveUserPermissions,
		finishResolutions: mockFinishResolutions,
	} ),
	select: () => ( {
		hasStartedResolution: mockHasStartedResolution,
	} ),
} ) );
vi.mock( '@wordpress/core-data', () => ( { store: { name: 'core' } } ) );

vi.mock( '../../../utils/bridge', () => ( {
	getGBKit: vi.fn(),
} ) );

import { getGBKit } from '../../../utils/bridge';

describe( 'useSeededPermissions', () => {
	beforeEach( () => {
		vi.clearAllMocks();
		mockHasStartedResolution.mockReturnValue( false );
	} );

	it( 'seeds attachment permissions when uploadFiles is true', () => {
		getGBKit.mockReturnValue( {
			userCapabilities: { uploadFiles: true },
		} );

		renderHook( () => useSeededPermissions() );

		expect( mockReceiveUserPermissions ).toHaveBeenCalledWith( {
			'create/postType/attachment': true,
			'read/postType/attachment': true,
			'update/postType/attachment': true,
			'delete/postType/attachment': true,
		} );
		expect( mockFinishResolutions ).toHaveBeenCalledWith( 'canUser', [
			[ 'create', { kind: 'postType', name: 'attachment' } ],
			[ 'read', { kind: 'postType', name: 'attachment' } ],
			[ 'update', { kind: 'postType', name: 'attachment' } ],
			[ 'delete', { kind: 'postType', name: 'attachment' } ],
		] );
	} );

	it( 'does nothing when userCapabilities is absent', () => {
		getGBKit.mockReturnValue( {} );

		renderHook( () => useSeededPermissions() );

		expect( mockReceiveUserPermissions ).not.toHaveBeenCalled();
		expect( mockFinishResolutions ).not.toHaveBeenCalled();
	} );

	it( 'does nothing when uploadFiles is not strictly true', () => {
		for ( const value of [ false, undefined, 'true', 1 ] ) {
			getGBKit.mockReturnValue( {
				userCapabilities: { uploadFiles: value },
			} );

			renderHook( () => useSeededPermissions() );
		}

		expect( mockReceiveUserPermissions ).not.toHaveBeenCalled();
		expect( mockFinishResolutions ).not.toHaveBeenCalled();
	} );

	it( 'does nothing when userCapabilities lacks uploadFiles', () => {
		getGBKit.mockReturnValue( {
			userCapabilities: {},
		} );

		renderHook( () => useSeededPermissions() );

		expect( mockReceiveUserPermissions ).not.toHaveBeenCalled();
		expect( mockFinishResolutions ).not.toHaveBeenCalled();
	} );

	it( 'early-returns when a canUser resolution is already in flight', () => {
		getGBKit.mockReturnValue( {
			userCapabilities: { uploadFiles: true },
		} );
		mockHasStartedResolution.mockReturnValue( true );

		renderHook( () => useSeededPermissions() );

		expect( mockHasStartedResolution ).toHaveBeenCalledWith( 'canUser', [
			'create',
			{ kind: 'postType', name: 'attachment' },
		] );
		expect( mockReceiveUserPermissions ).not.toHaveBeenCalled();
		expect( mockFinishResolutions ).not.toHaveBeenCalled();
	} );
} );
