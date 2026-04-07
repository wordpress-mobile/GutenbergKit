import { vi } from 'vitest';

// Stable map of mock dispatched actions for stores referenced by editor
// code (e.g. core/editor's `savePost`, `undo`, `redo`, `switchEditorMode`,
// and core/notices' `removeNotice`).
//
// Returning `vi.fn()` rather than `undefined` lets `useHostBridge` assign
// destructured actions directly (e.g. `window.editor.savePost = savePost`)
// without silently producing `undefined` values.
//
// Returning the *same* object on every call is important for tests that
// need to read the captured mock after the hook runs — e.g. `const
// { savePost } = useDispatch()` in a test must yield the very same
// `vi.fn` the hook destructured, so `mockResolvedValueOnce` and
// `toHaveBeenCalled` work end-to-end.
const dispatchedActions = {
	undo: vi.fn(),
	redo: vi.fn(),
	savePost: vi.fn(),
	switchEditorMode: vi.fn(),
	editEntityRecord: vi.fn(),
	updateBlock: vi.fn(),
	selectionChange: vi.fn(),
	removeNotice: vi.fn(),
};

export const useDispatch = vi.fn( () => dispatchedActions );
export const useSelect = vi.fn( ( selector ) => {
	if ( typeof selector === 'function' ) {
		return selector( () => ( {} ) );
	}
	return {};
} );
