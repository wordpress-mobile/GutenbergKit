import { vi } from 'vitest';

// Returns mock dispatched actions for stores referenced by editor code
// (e.g. core/editor's `savePost`, `undo`, `redo`, `switchEditorMode`).
// Returning `vi.fn()` rather than `undefined` lets `useHostBridge` assign
// destructured actions directly (e.g. `window.editor.savePost = savePost`)
// without silently producing `undefined` values.
export const useDispatch = vi.fn( () => ( {
	undo: vi.fn(),
	redo: vi.fn(),
	savePost: vi.fn(),
	switchEditorMode: vi.fn(),
	editEntityRecord: vi.fn(),
	updateBlock: vi.fn(),
	selectionChange: vi.fn(),
} ) );
export const useSelect = vi.fn( ( selector ) => {
	if ( typeof selector === 'function' ) {
		return selector( () => ( {} ) );
	}
	return {};
} );
