/**
 * External dependencies
 */
import { describe, it, expect, afterEach } from 'vitest';

/**
 * Internal dependencies
 */
import parseException from './exception-parser';

describe( 'parseException debug images', () => {
	afterEach( () => {
		delete window._sentryDebugIds;
	} );

	it( 'emits a debug image for each stack file that has a Debug ID', () => {
		// `sentry-cli sourcemaps inject` records `(new Error).stack -> debugId`;
		// the stack's top frame identifies the chunk the snippet ran in.
		window._sentryDebugIds = {
			'Error\n    at https://example.com/assets/editor-abc.js:1:1':
				'11111111-1111-1111-1111-111111111111',
			'Error\n    at https://example.com/assets/index-def.js:1:1':
				'22222222-2222-2222-2222-222222222222',
		};

		const exception = {
			name: 'TypeError',
			message: 'boom',
			stack: [
				'TypeError: boom',
				'    at fn (https://example.com/assets/editor-abc.js:22:247)',
				'    at go (https://example.com/assets/index-def.js:3:9)',
			].join( '\n' ),
		};

		const { debug_images: debugImages } = parseException( exception );

		expect( debugImages ).toEqual(
			expect.arrayContaining( [
				{
					code_file: 'https://example.com/assets/editor-abc.js',
					debug_id: '11111111-1111-1111-1111-111111111111',
				},
				{
					code_file: 'https://example.com/assets/index-def.js',
					debug_id: '22222222-2222-2222-2222-222222222222',
				},
			] )
		);
		expect( debugImages ).toHaveLength( 2 );
	} );

	it( 'deduplicates files that appear in multiple frames', () => {
		window._sentryDebugIds = {
			'Error\n    at https://example.com/assets/editor-abc.js:1:1':
				'11111111-1111-1111-1111-111111111111',
		};

		const exception = {
			name: 'Error',
			message: 'boom',
			stack: [
				'Error: boom',
				'    at a (https://example.com/assets/editor-abc.js:22:247)',
				'    at b (https://example.com/assets/editor-abc.js:30:5)',
			].join( '\n' ),
		};

		const { debug_images: debugImages } = parseException( exception );

		expect( debugImages ).toEqual( [
			{
				code_file: 'https://example.com/assets/editor-abc.js',
				debug_id: '11111111-1111-1111-1111-111111111111',
			},
		] );
	} );

	it( 'returns an empty list when no Debug IDs are present', () => {
		const exception = {
			name: 'Error',
			message: 'boom',
			stack: 'Error: boom\n    at a (https://example.com/assets/editor-abc.js:1:1)',
		};

		const { debug_images: debugImages } = parseException( exception );

		expect( debugImages ).toEqual( [] );
	} );
} );
