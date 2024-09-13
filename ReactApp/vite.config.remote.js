import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { defaultRequestToExternal } from '@wordpress/dependency-extraction-webpack-plugin/lib/util.js';
import MagicString from 'magic-string';

export default defineConfig({
	base: '',
	build: {
		rollupOptions: {
			input: 'remote.html',
			external: externalize,
		},
		target: 'esnext',
	},
	plugins: [react(), wordPressExternals()],
});

function externalize(id) {
	const externalDefinition = defaultRequestToExternal(id);
	return (
		!!externalDefinition &&
		!id.endsWith('.css') &&
		!['apiFetch', 'i18n', 'url', 'hooks'].includes(
			externalDefinition[externalDefinition.length - 1]
		)
	);
}

/**
 * Transform code by replacing WordPress imports with global definitions.
 *
 * @returns {object} The transformed code and map.
 */
function wordPressExternals() {
	return {
		name: 'wordpress-externals-plugin',
		transform(code, id) {
			const magicString = new MagicString(code);
			let hasReplacements = false;

			// Match WordPress and React JSX runtime import statements
			const regex =
				/import\s*(?:{([^}]+)}\s*from)?\s*['"](@wordpress\/([^'"]+)|react\/jsx-runtime)['"];/g;
			let match;

			while ((match = regex.exec(code)) !== null) {
				const [fullMatch, imports, module] = match;
				const externalDefinition = defaultRequestToExternal(module);

				if (
					!externalDefinition ||
					/@wordpress\/(api-fetch|i18n|url)/.test(id)
				) {
					continue; // Exclude the module from externalization
				}

				hasReplacements = true;

				if (!imports) {
					// Remove the side effect import entirely
					magicString.remove(
						match.index,
						match.index + fullMatch.length
					);
					continue;
				}

				const importList = imports.split(',').map((i) => {
					const parts = i.trim().split(/\s+as\s+/);
					if (parts.length === 2) {
						// Convert import "as" syntax to destructuring assignment
						return `${parts[0]}: ${parts[1]}`;
					}
					return i.trim();
				});

				const definitionArray = Array.isArray(externalDefinition)
					? externalDefinition
					: [externalDefinition];

				const replacement = `const { ${importList.join(', ')} } = window.${definitionArray.join('.')};`;
				magicString.overwrite(
					match.index,
					match.index + fullMatch.length,
					replacement
				);
			}

			if (!hasReplacements) {
				return null;
			}

			return {
				code: magicString.toString(),
				map: magicString.generateMap({ hires: true }),
			};
		},
	};
}
