import { describe, it, expect, vi } from 'vitest';
import { buildPostTypeEntity, prePersistPostType } from './post-type-entities';

// Loading the real package in vitest trips on JSON import attributes.
vi.mock( '@wordpress/blocks', () => ( { parse: vi.fn() } ) );

describe( 'buildPostTypeEntity', () => {
	const entity = buildPostTypeEntity( {
		type: 'book',
		restBase: 'books',
		restNamespace: 'wp/v2',
	} );

	it( "matches core's post type entity configuration", () => {
		expect( entity ).toMatchObject( {
			kind: 'postType',
			name: 'book',
			baseURL: '/wp/v2/books',
			baseURLParams: { context: 'edit' },
			transientEdits: { selection: true },
			mergedEdits: { meta: true },
			rawAttributes: [ 'title', 'excerpt', 'content' ],
			__unstablePrePersist: prePersistPostType,
			__unstable_rest_base: 'books',
			supportsPagination: true,
			revisionKey: 'id',
		} );
	} );

	it( 'builds revision URLs', () => {
		expect( entity.getRevisionsUrl( 5 ) ).toBe(
			'/wp/v2/books/5/revisions'
		);
		expect( entity.getRevisionsUrl( 5, 9 ) ).toBe(
			'/wp/v2/books/5/revisions/9'
		);
	} );
} );

describe( 'prePersistPostType', () => {
	it( 'saves an auto-draft as a draft with an empty title', () => {
		expect( prePersistPostType( { status: 'auto-draft' }, {} ) ).toEqual( {
			status: 'draft',
			title: '',
		} );
	} );

	it( 'keeps the status and title being saved', () => {
		expect(
			prePersistPostType(
				{ status: 'auto-draft' },
				{ status: 'publish', title: 'Title' }
			)
		).toEqual( {} );
	} );

	it( 'leaves posts that are not auto-drafts unchanged', () => {
		expect( prePersistPostType( { status: 'draft' }, {} ) ).toEqual( {} );
	} );
} );
