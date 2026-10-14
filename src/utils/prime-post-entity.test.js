import { describe, it, expect, beforeEach, vi } from 'vitest';
import { dispatch, resolveSelect, select } from '@wordpress/data';
import { primePostEntity } from './prime-post-entity';
import { getGBKit } from './bridge';
import { buildPostTypeEntity } from './post-type-entities';

// Loading the real core-data store in vitest trips on its ESM dependencies.
vi.mock( '@wordpress/data', () => ( {
	dispatch: vi.fn(),
	resolveSelect: vi.fn(),
	select: vi.fn(),
} ) );
vi.mock( '@wordpress/core-data', () => ( { store: 'core' } ) );
vi.mock( './bridge' );
vi.mock( './logger' );
vi.mock( './post-type-entities', () => ( {
	buildPostTypeEntity: vi.fn( () => ( { name: 'fallback' } ) ),
} ) );

/**
 * Builds a post shaped like the one `getPost()` returns.
 *
 * @param {Object} overrides Fields to override.
 * @return {Object} The post.
 */
function buildPost( overrides = {} ) {
	return {
		id: 1,
		type: 'post',
		restBase: 'posts',
		restNamespace: 'wp/v2',
		status: 'draft',
		title: { raw: 'Host title' },
		content: { raw: '<p>Host content</p>' },
		...overrides,
	};
}

describe( 'primePostEntity', () => {
	let coreDispatch;
	let getEntityConfig;
	let getEntitiesConfig;

	beforeEach( () => {
		vi.clearAllMocks();

		coreDispatch = {
			addEntities: vi.fn(),
			receiveEntityRecords: vi.fn(),
			finishResolution: vi.fn(),
		};
		getEntityConfig = vi.fn( () => ( { name: 'post' } ) );
		getEntitiesConfig = vi.fn( () => Promise.resolve( [] ) );

		dispatch.mockReturnValue( coreDispatch );
		select.mockReturnValue( { getEntityConfig } );
		resolveSelect.mockReturnValue( { getEntitiesConfig } );
		getGBKit.mockReturnValue( {} );
	} );

	it( "loads core's post type entities before seeding", async () => {
		await primePostEntity( buildPost() );

		expect( getEntitiesConfig ).toHaveBeenCalledWith( 'postType' );
		expect( getEntityConfig ).toHaveBeenCalledWith( 'postType', 'post' );
		expect( coreDispatch.addEntities ).not.toHaveBeenCalled();
	} );

	it( 'registers a fallback entity for a post type core did not load', async () => {
		getEntityConfig.mockReturnValue( undefined );
		const post = buildPost( { type: 'book', restBase: 'books' } );

		await primePostEntity( post );

		expect( buildPostTypeEntity ).toHaveBeenCalledWith( post );
		expect( coreDispatch.addEntities ).toHaveBeenCalledWith( [
			{ name: 'fallback' },
		] );
	} );

	it( 'marks the post resolved so core-data never fetches it', async () => {
		await primePostEntity( buildPost( { id: 2 } ) );

		expect( coreDispatch.finishResolution ).toHaveBeenCalledWith(
			'getEntityRecord',
			[ 'postType', 'post', 2 ]
		);
	} );

	it( 'seeds the host post when the server record is not preloaded', async () => {
		const post = buildPost( { id: -1 } );

		await primePostEntity( post );

		expect( coreDispatch.receiveEntityRecords ).toHaveBeenCalledWith(
			'postType',
			'post',
			post
		);
	} );

	it( 'seeds the preloaded server record with the host title and content', async () => {
		getGBKit.mockReturnValue( {
			preloadData: {
				'/wp/v2/posts/3?context=edit': {
					body: {
						id: 3,
						type: 'post',
						status: 'publish',
						author: 7,
						title: {
							raw: 'Server title',
							rendered: 'Server title',
						},
						content: {
							raw: '<p>Server content</p>',
							rendered: '<p>Server content</p>',
							protected: false,
						},
					},
				},
			},
		} );

		await primePostEntity( buildPost( { id: 3 } ) );

		expect( coreDispatch.receiveEntityRecords ).toHaveBeenCalledWith(
			'postType',
			'post',
			{
				id: 3,
				type: 'post',
				status: 'publish',
				author: 7,
				title: { raw: 'Host title', rendered: 'Server title' },
				content: {
					raw: '<p>Host content</p>',
					rendered: '<p>Server content</p>',
					protected: false,
				},
			}
		);
	} );
} );
