import { vi } from 'vitest';

export const useDispatch = vi.fn( () => ( {} ) );
export const useSelect = vi.fn( ( selector ) => {
	if ( typeof selector === 'function' ) {
		return selector( () => ( {} ) );
	}
	return {};
} );
