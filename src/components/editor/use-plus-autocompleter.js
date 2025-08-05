/**
 * WordPress dependencies
 */
import { addFilter, removeFilter } from '@wordpress/hooks';
import { useEffect } from '@wordpress/element';

/*
 * Internal dependencies
 */
import { info } from '../../utils/logger';

/**
 * Adds a filter for the Autocomplete completers to show an alert when + is typed.
 *
 * @return {void}
 */
export function usePlusAutocompleter() {
	useEffect( () => {
		addFilter(
			'editor.Autocomplete.completers',
			'GutenbergKit/plus-symbol-alert',
			addPlusSymbolCompleter
		);

		return () => {
			removeFilter(
				'editor.Autocomplete.completers',
				'GutenbergKit/plus-symbol-alert'
			);
		};
	}, [] );
}

/**
 * Adds the + symbol autocompleter to the completers array.
 *
 * @param {Array} completers Existing completers.
 * @return {Array} Updated completers array.
 */
function addPlusSymbolCompleter( completers = [] ) {
	const plusSymbolCompleter = {
		name: 'plus-symbol',
		triggerPrefix: '+',
		options: () => {
			info( 'You typed a + symbol!' );
			// Return empty array since we're not providing actual completion options
			return [];
		},
		getOptionLabel: () => '',
		getOptionCompletion: () => '+',
	};

	return [ ...completers, plusSymbolCompleter ];
}
