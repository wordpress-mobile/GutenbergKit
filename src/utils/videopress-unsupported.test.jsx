import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import {
	addFilter,
	applyFilters,
	hasFilter,
	removeAllFilters,
} from '@wordpress/hooks';
import { initializeVideoPressUnsupportedBlock } from './videopress-unsupported';
import { warn } from './logger';

vi.mock( './logger' );

vi.mock( '../components/videopress-unsupported', () => ( {
	default: () => <div data-testid="videopress-unsupported" />,
} ) );

const identity = ( component ) => component;

describe( 'initializeVideoPressUnsupportedBlock', () => {
	beforeEach( () => {
		vi.clearAllMocks();
	} );

	afterEach( () => {
		removeAllFilters( 'editor.BlockListBlock' );
		removeAllFilters( 'blocks.registerBlockType' );
		removeAllFilters( 'editor.BlockEdit' );
	} );

	it( "removes Jetpack's conversion filter", () => {
		addJetpackFilters();

		initializeVideoPressUnsupportedBlock();

		expect(
			hasFilter(
				'editor.BlockListBlock',
				'videopress/jetpack-convert-from-v6-to-v5'
			)
		).toBe( false );
		expect( warn ).not.toHaveBeenCalled();
	} );

	it( "warns when Jetpack's extension is present but the conversion filter is missing", () => {
		addFilter( 'blocks.registerBlockType', 'jetpack/videopress', identity );

		initializeVideoPressUnsupportedBlock();

		expect( warn ).toHaveBeenCalledTimes( 1 );
		expect(
			hasFilter(
				'editor.BlockEdit',
				'gutenberg-kit/videopress-unsupported'
			)
		).toBe( true );
	} );

	it( 'does nothing when Jetpack VideoPress is absent', () => {
		initializeVideoPressUnsupportedBlock();

		expect( warn ).not.toHaveBeenCalled();
		expect(
			hasFilter(
				'editor.BlockEdit',
				'gutenberg-kit/videopress-unsupported'
			)
		).toBe( false );
	} );

	it( 'renders the placeholder for unsupported VideoPress blocks', () => {
		addJetpackFilters();
		initializeVideoPressUnsupportedBlock();

		renderBlockEdit( {
			name: 'core/missing',
			attributes: { originalName: 'videopress/video' },
		} );

		expect(
			screen.getByTestId( 'videopress-unsupported' )
		).toBeInTheDocument();
		expect( screen.queryByTestId( 'block-edit' ) ).not.toBeInTheDocument();
	} );

	it.each( [
		[
			'other missing blocks',
			{
				name: 'core/missing',
				attributes: { originalName: 'some/block' },
			},
		],
		[ 'core/video blocks', { name: 'core/video', attributes: {} } ],
	] )( 'passes %s through unchanged', ( _, props ) => {
		addJetpackFilters();
		initializeVideoPressUnsupportedBlock();

		renderBlockEdit( props );

		expect( screen.getByTestId( 'block-edit' ) ).toBeInTheDocument();
		expect(
			screen.queryByTestId( 'videopress-unsupported' )
		).not.toBeInTheDocument();
	} );
} );

function addJetpackFilters() {
	addFilter(
		'editor.BlockListBlock',
		'videopress/jetpack-convert-from-v6-to-v5',
		identity
	);
	addFilter( 'blocks.registerBlockType', 'jetpack/videopress', identity );
}

function renderBlockEdit( props ) {
	const BlockEdit = applyFilters( 'editor.BlockEdit', () => (
		<div data-testid="block-edit" />
	) );
	render( <BlockEdit { ...props } /> );
}
