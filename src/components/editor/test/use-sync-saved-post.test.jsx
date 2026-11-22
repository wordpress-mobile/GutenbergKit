import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook } from '@testing-library/react';
import { useSyncSavedPost } from '../use-sync-saved-post';
import { onSavedPostChanged } from '../../../utils/bridge';

let editorState;

vi.mock( '@wordpress/data', () => ( {
	useSelect: ( mapSelect ) =>
		mapSelect( ( store ) =>
			store === 'core'
				? { getEntityRecord: () => editorState.savedPost }
				: {
						getCurrentPostType: () => 'post',
						getCurrentPostId: () => editorState.id,
				  }
		),
} ) );

vi.mock( '@wordpress/core-data', () => ( { store: 'core' } ) );
vi.mock( '@wordpress/editor', () => ( { store: 'core/editor' } ) );

vi.mock( '../../../utils/bridge', () => ( {
	onSavedPostChanged: vi.fn(),
} ) );

const opened = {
	id: 42,
	modified_gmt: '2024-01-16T00:00:00',
	title: { raw: 'Opened', rendered: 'Opened' },
	excerpt: { raw: '', rendered: '' },
};

describe( 'useSyncSavedPost', () => {
	beforeEach( () => {
		vi.clearAllMocks();
		editorState = { id: 42, savedPost: opened };
	} );

	it( 'does not report the version the editor opened with', () => {
		const { rerender } = renderHook( () => useSyncSavedPost() );
		rerender();

		expect( onSavedPostChanged ).not.toHaveBeenCalled();
	} );

	it( 'reports a changed saved version with its date and changed fields', () => {
		const { rerender } = renderHook( () => useSyncSavedPost() );

		editorState.savedPost = {
			...opened,
			excerpt: { raw: 'From a list', rendered: 'From a list' },
		};
		rerender();

		expect( onSavedPostChanged ).toHaveBeenCalledTimes( 1 );
		expect( onSavedPostChanged ).toHaveBeenCalledWith( {
			modified_gmt: '2024-01-16T00:00:00',
			fields: {
				excerpt: { raw: 'From a list', rendered: 'From a list' },
			},
		} );
	} );

	it( 'starts over without a report when the post gets a new ID', () => {
		editorState = { id: -1, savedPost: { id: -1, title: { raw: '' } } };
		const { rerender } = renderHook( () => useSyncSavedPost() );

		editorState = { id: 42, savedPost: opened };
		rerender();

		expect( onSavedPostChanged ).not.toHaveBeenCalled();
	} );
} );
