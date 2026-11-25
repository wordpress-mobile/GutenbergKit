import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import { useSelect } from '@wordpress/data';
import VideoPressUnsupported from '.';

vi.mock( '@wordpress/block-editor', () => ( {
	useBlockProps: ( props ) => props,
} ) );

vi.mock( '@wordpress/components', () => ( {
	SandBox: ( { html } ) => <div data-testid="sandbox">{ html }</div>,
	Spinner: () => <div data-testid="spinner" />,
} ) );

vi.mock( '@wordpress/core-data', () => ( { store: 'core' } ) );

vi.mock( '@wordpress/data', () => ( { useSelect: vi.fn() } ) );

const ORIGINAL_CONTENT =
	'<!-- wp:videopress/video {"guid":"AbC123xy","isPrivate":true} /-->';

describe( 'VideoPressUnsupported', () => {
	let getEmbedPreview;

	beforeEach( () => {
		getEmbedPreview = vi.fn();
		useSelect.mockImplementation( ( callback ) =>
			callback( () => ( { getEmbedPreview } ) )
		);
	} );

	it( "requests the preview for the block's guid", () => {
		renderPlaceholder();

		expect( getEmbedPreview ).toHaveBeenCalledWith(
			'https://videopress.com/v/AbC123xy'
		);
	} );

	it( 'shows a spinner while the preview loads', () => {
		getEmbedPreview.mockReturnValue( undefined );

		renderPlaceholder();

		expect( screen.getByTestId( 'spinner' ) ).toBeInTheDocument();
		expect( screen.queryByTestId( 'sandbox' ) ).not.toBeInTheDocument();
	} );

	it( 'renders the preview once loaded', () => {
		getEmbedPreview.mockReturnValue( { html: '<iframe></iframe>' } );

		renderPlaceholder();

		expect( screen.getByTestId( 'sandbox' ) ).toHaveTextContent(
			'<iframe></iframe>'
		);
		expect( screen.queryByTestId( 'spinner' ) ).not.toBeInTheDocument();
	} );

	it.each( [
		[
			"the video's aspect ratio",
			{ width: 600, height: 338 },
			'600 / 338',
		],
		[ '16:9 without a size', {}, '16 / 9' ],
	] )( 'sizes the preview by %s', ( _, size, expected ) => {
		getEmbedPreview.mockReturnValue( {
			html: '<iframe></iframe>',
			...size,
		} );

		renderPlaceholder();

		expect(
			screen.getByTestId( 'sandbox' ).parentElement.style.aspectRatio
		).toBe( expected );
	} );

	it( 'shows an empty box when the preview fails', () => {
		getEmbedPreview.mockReturnValue( false );

		renderPlaceholder();

		expect( screen.queryByTestId( 'spinner' ) ).not.toBeInTheDocument();
		expect( screen.queryByTestId( 'sandbox' ) ).not.toBeInTheDocument();
	} );

	it.each( [
		[ 'no guid', '<!-- wp:videopress/video {"id":1} /-->' ],
		[
			'an invalid guid',
			'<!-- wp:videopress/video {"guid":"a/../b"} /-->',
		],
		[ 'no markup', null ],
	] )( 'skips the preview request for %s', ( _, originalContent ) => {
		renderPlaceholder( originalContent );

		expect( getEmbedPreview ).not.toHaveBeenCalled();
		expect( screen.queryByTestId( 'spinner' ) ).not.toBeInTheDocument();
	} );

	it( 'captions the video to explain that its settings are not editable', () => {
		renderPlaceholder();

		expect(
			screen.getByRole( 'figure' ).querySelector( 'figcaption' )
		).toHaveTextContent(
			'Editing VideoPress settings is not yet supported in the app.'
		);
	} );
} );

function renderPlaceholder( originalContent = ORIGINAL_CONTENT ) {
	render(
		<VideoPressUnsupported
			attributes={ {
				originalName: 'videopress/video',
				originalContent,
			} }
		/>
	);
}
