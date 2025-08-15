/**
 * WordPress dependencies
 */
import { addFilter, removeFilter } from '@wordpress/hooks';
import { render, renderHook } from '@testing-library/react';

/**
 * Internal dependencies
 */
import { useMediaUpload } from '../use-media-upload';
import {
	describe,
	it,
	expect,
	vi,
	beforeAll,
	afterAll,
	afterEach,
} from 'vitest';
import { openMediaLibrary } from '../../../utils/bridge';

vi.mock( '@wordpress/hooks' );
vi.mock( '../../../utils/bridge', { spy: true } );

describe( 'useMediaUpload', () => {
	beforeAll( () => {
		vi.stubGlobal( 'editor', {
			setMediaUploadAttachment: vi.fn(),
		} );
	} );

	afterEach( () => {
		vi.clearAllMocks();
	} );

	afterAll( () => {
		vi.restoreAllMocks();
	} );

	it( 'should add the MediaUpload filter when mounted', () => {
		renderHook( () => useMediaUpload() );

		expect( addFilter ).toHaveBeenCalledWith(
			'editor.MediaUpload',
			'GutenbergKit',
			expect.any( Function )
		);
	} );

	it( 'should remove the MediaUpload filter when unmounted', () => {
		const { unmount } = renderHook( () => useMediaUpload() );

		unmount();

		expect( removeFilter ).toHaveBeenCalledWith(
			'editor.MediaUpload',
			'GutenbergKit'
		);
	} );

	it( 'should define the setMediaUploadAttachment function', () => {
		let MediaUploadComponent;
		addFilter.mockImplementation( ( name, namespace, callback ) => {
			MediaUploadComponent = callback();
		} );
		const onSelect = vi.fn();

		renderHook( () => useMediaUpload() );
		render(
			<MediaUploadComponent
				render={ ( { open } ) => open() }
				onSelect={ onSelect }
				multiple={ false }
			/>
		);
		window.editor.setMediaUploadAttachment( [ 'test' ] );

		expect( onSelect ).toHaveBeenCalledWith( 'test' );
	} );

	it( 'should clear the setMediaUploadAttachment function when the component is unmounted', () => {
		let MediaUploadComponent;
		addFilter.mockImplementation( ( name, namespace, callback ) => {
			MediaUploadComponent = callback();
		} );
		const onSelect = vi.fn();

		renderHook( () => useMediaUpload() );
		const { unmount } = render(
			<MediaUploadComponent
				render={ ( { open } ) => open() }
				onSelect={ onSelect }
				multiple={ false }
			/>
		);

		window.editor.setMediaUploadAttachment( [ 'test' ] );

		expect( onSelect ).toHaveBeenCalledWith( 'test' );

		unmount();

		window.editor.setMediaUploadAttachment( [ 'test' ] );

		expect( onSelect ).toHaveBeenCalledTimes( 1 );
	} );

	it( 'should open the media library when the filter is called', () => {
		let MediaUploadComponent;
		addFilter.mockImplementation( ( name, namespace, callback ) => {
			MediaUploadComponent = callback();
		} );

		renderHook( () => useMediaUpload() );
		render(
			<MediaUploadComponent
				render={ ( { open } ) => open() }
				onSelect={ vi.fn() }
				multiple={ false }
			/>
		);

		expect( openMediaLibrary ).toHaveBeenCalled();
	} );

	it( 'should always provide a multiple argument to the openMediaLibrary callback', () => {
		let MediaUploadComponent;
		addFilter.mockImplementation( ( name, namespace, callback ) => {
			MediaUploadComponent = callback();
		} );

		renderHook( () => useMediaUpload() );
		render(
			<MediaUploadComponent
				render={ ( { open } ) => open() }
				onSelect={ vi.fn() }
			/>
		);

		expect( openMediaLibrary ).toHaveBeenCalledWith( { multiple: false } );
	} );
} );
