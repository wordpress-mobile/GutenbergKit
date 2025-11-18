/**
 * WordPress dependencies
 */
import { addFilter, removeFilter } from '@wordpress/hooks';
import { render, renderHook, waitFor } from '@testing-library/react';

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
import { warn } from '../../../utils/logger';

vi.mock( '@wordpress/hooks' );
vi.mock( '../../../utils/bridge', { spy: true } );
vi.mock( '../../../utils/logger', () => ( {
	warn: vi.fn(),
	error: vi.fn(),
	info: vi.fn(),
	debug: vi.fn(),
} ) );

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

	it( 'should define the setMediaUploadAttachment function', async () => {
		let MediaUploadComponent;
		addFilter.mockImplementation( ( name, namespace, callback ) => {
			MediaUploadComponent = callback();
		} );
		const onSelect = vi.fn();
		let openPicker;

		renderHook( () => useMediaUpload() );
		render(
			<MediaUploadComponent
				render={ ( { open } ) => {
					openPicker = open;
					return null;
				} }
				onSelect={ onSelect }
				multiple={ false }
			/>
		);

		// Wait for effects to run and get the contextId
		await waitFor( () => {
			openPicker();
		} );

		const contextId = openMediaLibrary.mock.calls[ 0 ][ 0 ].contextId;
		window.editor.setMediaUploadAttachment( [ 'test' ], contextId );

		expect( onSelect ).toHaveBeenCalledWith( 'test' );
	} );

	it( 'should clear the setMediaUploadAttachment function when the component is unmounted', async () => {
		let MediaUploadComponent;
		addFilter.mockImplementation( ( name, namespace, callback ) => {
			MediaUploadComponent = callback();
		} );
		const onSelect = vi.fn();
		let openPicker;

		renderHook( () => useMediaUpload() );
		const { unmount } = render(
			<MediaUploadComponent
				render={ ( { open } ) => {
					openPicker = open;
					return null;
				} }
				onSelect={ onSelect }
				multiple={ false }
			/>
		);

		// Wait for effects to run and get the contextId
		await waitFor( () => {
			openPicker();
		} );

		const contextId = openMediaLibrary.mock.calls[ 0 ][ 0 ].contextId;
		window.editor.setMediaUploadAttachment( [ 'test' ], contextId );

		expect( onSelect ).toHaveBeenCalledWith( 'test' );

		unmount();

		// After unmount, calling with the same contextId should not trigger callback
		window.editor.setMediaUploadAttachment( [ 'test' ], contextId );

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

		expect( openMediaLibrary ).toHaveBeenCalledWith(
			expect.objectContaining( { multiple: false } )
		);
	} );

	describe( 'Context ID routing for multiple MediaPlaceholder instances', () => {
		it( 'should route media to the correct callback when multiple instances exist', async () => {
			let MediaUploadComponent;
			addFilter.mockImplementation( ( name, namespace, callback ) => {
				MediaUploadComponent = callback();
			} );

			const onSelectBefore = vi.fn();
			const onSelectAfter = vi.fn();
			let openBefore;
			let openAfter;

			renderHook( () => useMediaUpload() );

			// Render two MediaPlaceholder instances (like in Image Compare block)
			render(
				<>
					<MediaUploadComponent
						render={ ( { open } ) => {
							openBefore = open;
							return null;
						} }
						onSelect={ onSelectBefore }
						multiple={ false }
					/>
					<MediaUploadComponent
						render={ ( { open } ) => {
							openAfter = open;
							return null;
						} }
						onSelect={ onSelectAfter }
						multiple={ false }
					/>
				</>
			);

			// Wait for effects to run and call open() after component is mounted
			await waitFor( () => {
				openBefore();
				openAfter();
			} );

			// Get the contextId from the openMediaLibrary calls
			const firstCallArgs = openMediaLibrary.mock.calls[ 0 ][ 0 ];
			const contextIdBefore = firstCallArgs.contextId;

			const secondCallArgs = openMediaLibrary.mock.calls[ 1 ][ 0 ];
			const contextIdAfter = secondCallArgs.contextId;

			// Verify both contextIds are unique
			expect( contextIdBefore ).toBeDefined();
			expect( contextIdAfter ).toBeDefined();
			expect( contextIdBefore ).not.toBe( contextIdAfter );

			// Simulate native returning media to the "before" slot
			window.editor.setMediaUploadAttachment(
				[ 'image-before.jpg' ],
				contextIdBefore
			);

			expect( onSelectBefore ).toHaveBeenCalledWith( 'image-before.jpg' );
			expect( onSelectAfter ).not.toHaveBeenCalled();

			// Simulate native returning media to the "after" slot
			window.editor.setMediaUploadAttachment(
				[ 'image-after.jpg' ],
				contextIdAfter
			);

			expect( onSelectAfter ).toHaveBeenCalledWith( 'image-after.jpg' );
			expect( onSelectBefore ).toHaveBeenCalledTimes( 1 );
		} );

		it( 'should warn when an invalid contextId is provided', () => {
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

			// Call with an invalid contextId
			window.editor.setMediaUploadAttachment(
				[ 'test-image.jpg' ],
				'invalid-context-id'
			);

			expect( warn ).toHaveBeenCalledWith(
				expect.stringContaining( 'No callback found for contextId' )
			);
		} );

		it( 'should clean up callback from registry when component unmounts', () => {
			let MediaUploadComponent;
			addFilter.mockImplementation( ( name, namespace, callback ) => {
				MediaUploadComponent = callback();
			} );

			const onSelectFirst = vi.fn();
			const onSelectSecond = vi.fn();

			renderHook( () => useMediaUpload() );

			const { unmount } = render(
				<>
					<MediaUploadComponent
						render={ ( { open } ) => open() }
						onSelect={ onSelectFirst }
						multiple={ false }
					/>
					<MediaUploadComponent
						render={ ( { open } ) => open() }
						onSelect={ onSelectSecond }
						multiple={ false }
					/>
				</>
			);

			// Get contextIds before unmounting
			const firstCallArgs = openMediaLibrary.mock.calls[ 0 ][ 0 ];
			const secondCallArgs = openMediaLibrary.mock.calls[ 1 ][ 0 ];
			const contextIdFirst = firstCallArgs.contextId;
			const contextIdSecond = secondCallArgs.contextId;

			// Unmount both components
			unmount();

			// Try to use the contextIds after unmount
			window.editor.setMediaUploadAttachment(
				[ 'image1.jpg' ],
				contextIdFirst
			);
			window.editor.setMediaUploadAttachment(
				[ 'image2.jpg' ],
				contextIdSecond
			);

			// Neither callback should be called since they were cleaned up
			expect( onSelectFirst ).not.toHaveBeenCalled();
			expect( onSelectSecond ).not.toHaveBeenCalled();
		} );

		it( 'should pass contextId to openMediaLibrary when opening picker', async () => {
			let MediaUploadComponent;
			addFilter.mockImplementation( ( name, namespace, callback ) => {
				MediaUploadComponent = callback();
			} );

			let openPicker;

			renderHook( () => useMediaUpload() );
			render(
				<MediaUploadComponent
					render={ ( { open } ) => {
						openPicker = open;
						return null;
					} }
					onSelect={ vi.fn() }
					allowedTypes={ [ 'image' ] }
					multiple={ false }
					value={ 123 }
				/>
			);

			// Wait for effects to run and then call open()
			await waitFor( () => {
				openPicker();
			} );

			expect( openMediaLibrary ).toHaveBeenCalledWith(
				expect.objectContaining( {
					allowedTypes: [ 'image' ],
					multiple: false,
					value: 123,
					contextId: expect.stringMatching( /^media-upload-\d+$/ ),
				} )
			);
		} );
	} );
} );
