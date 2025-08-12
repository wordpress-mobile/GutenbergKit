/**
 * WordPress dependencies
 */
import { addFilter, removeFilter } from '@wordpress/hooks';
import { useEffect } from '@wordpress/element';

/**
 * Internal dependencies
 */
import { onAutocompleterTriggered } from '../../utils/bridge';

/**
 * Adds a filter for the Autocomplete completers to show an alert when @ is typed.
 *
 * @return {void}
 */
export function useAtAutocompleter() {
	useEffect( () => {
		// Avoid conflicts with core's default autocompleter
		removeFilter(
			'editor.Autocomplete.completers',
			'editor/autocompleters/set-default-completers'
		);

		addFilter(
			'editor.Autocomplete.completers',
			'GutenbergKit/at-symbol-alert',
			addAtSymbolCompleter
		);

		return () => {
			removeFilter(
				'editor.Autocomplete.completers',
				'GutenbergKit/at-symbol-alert'
			);
		};
	}, [] );
}

/**
 * Adds the @ symbol autocompleter to the completers array.
 *
 * @param {Array} completers Existing completers.
 * @return {Array} Updated completers array.
 */
function addAtSymbolCompleter( completers = [] ) {
	const atSymbolCompleter = {
		name: 'at-symbol',
		triggerPrefix: '@',
		options: ( filterValue ) => {
			// Only trigger when cursor is directly after @ (no characters typed yet)
			if ( filterValue === '' ) {
				onAutocompleterTriggered( 'at-symbol' );
			}
			// Return empty array since we're not providing actual completion options
			return [];
		},
		allowContext: ( before, after ) => {
			const beforeEmptyOrWhitespace = /^$|\s$/.test( before );
			const afterEmptyOrWhitespace = /^$|^\s/.test( after );
			return beforeEmptyOrWhitespace && afterEmptyOrWhitespace;
		},
		isDebounced: true,
	};

	return [ ...completers, atSymbolCompleter ];
}
