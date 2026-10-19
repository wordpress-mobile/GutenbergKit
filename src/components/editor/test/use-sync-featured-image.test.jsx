import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook } from '@testing-library/react';
import { useSyncFeaturedImage } from '../use-sync-featured-image';
import { onEditorFeaturedImageChanged } from '../../../utils/bridge';

const mockGetEditedPostAttribute = vi.fn();

vi.mock( '@wordpress/data', () => ( {
	useSelect: ( mapSelect ) =>
		mapSelect( () => ( {
			getEditedPostAttribute: mockGetEditedPostAttribute,
		} ) ),
} ) );
vi.mock( '@wordpress/editor' );
vi.mock( '../../../utils/bridge' );

describe( 'useSyncFeaturedImage', () => {
	beforeEach( () => {
		vi.clearAllMocks();
	} );

	it( 'does not report the featured image the post loaded with', () => {
		mockGetEditedPostAttribute.mockReturnValue( 123 );

		renderHook( () => useSyncFeaturedImage() );

		expect( onEditorFeaturedImageChanged ).not.toHaveBeenCalled();
	} );

	it( 'reports a featured image set in the editor', () => {
		mockGetEditedPostAttribute.mockReturnValue( 123 );
		const { rerender } = renderHook( () => useSyncFeaturedImage() );

		mockGetEditedPostAttribute.mockReturnValue( 456 );
		rerender();

		expect( onEditorFeaturedImageChanged ).toHaveBeenCalledWith( 456 );
	} );

	it( 'reports the initial featured image when set again in the editor', () => {
		mockGetEditedPostAttribute.mockReturnValue( 123 );
		const { rerender } = renderHook( () => useSyncFeaturedImage() );

		mockGetEditedPostAttribute.mockReturnValue( 456 );
		rerender();
		mockGetEditedPostAttribute.mockReturnValue( 123 );
		rerender();

		expect( onEditorFeaturedImageChanged ).toHaveBeenLastCalledWith( 123 );
	} );

	it( 'does not report a removed featured image', () => {
		mockGetEditedPostAttribute.mockReturnValue( 123 );
		const { rerender } = renderHook( () => useSyncFeaturedImage() );

		mockGetEditedPostAttribute.mockReturnValue( 0 );
		rerender();

		expect( onEditorFeaturedImageChanged ).not.toHaveBeenCalled();
	} );
} );
