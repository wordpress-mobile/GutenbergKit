import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { defaultRequestToExternal } from '@wordpress/dependency-extraction-webpack-plugin/lib/util.js';

// https://vitejs.dev/config/
export default defineConfig({
	base: '',
	build: {
		rollupOptions: {
			external: externalize,
			output: {
				format: 'iife',
				globals: globalize,
				entryFileNames: `assets/[name].js`,
				chunkFileNames: `assets/[name].js`,
				assetFileNames: `assets/[name].[ext]`,
			},
		},
	},
	plugins: [react({ jsxRuntime: 'classic' }), wordPressExternals()],
});

const externalMap = new Map();

function externalize(id) {
	const result = defaultRequestToExternal(id);
	const isExternal = !!result;
	if (isExternal) externalMap.set(id, result);
	return isExternal;
}

function globalize(id) {
	let globalName = externalMap.get(id);
	if (Array.isArray(globalName)) return globalName.join('.');
	return globalName;
}

function wordPressExternals() {
	return {
		name: 'wordpress-externals-plugin',
		transform(code) {
			// Transform @wordpress imports, including renames
			code = code.replace(
				/import\s*{([^}]+)}\s*from\s*['"]@wordpress\/([^'"]+)['"]/g,
				(match, imports, module) => {
					const importList = imports.split(',').map((i) => {
						const parts = i.trim().split(/\s+as\s+/);
						if (parts.length === 2) {
							// Handle rename
							return `${parts[0]}: ${parts[1]}`;
						}
						return i.trim();
					});

					// Convert module name to camelCase for wp.moduleName format
					const wpModule = module.replace(/-([a-z])/g, (g) =>
						g[1].toUpperCase()
					);

					return `const { ${importList.join(', ')} } = window.wp.${wpModule}`;
				}
			);

			return {
				code,
				map: null, // we're not generating sourcemaps for this transformation
			};
		},
	};
}
