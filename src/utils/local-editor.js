/**
 * Loads the editor assets for the local editor.
 *
 * @return {Promise<Object>} The editor assets.
 */
export async function loadEditorAssets() {
	const { createRoot, StrictMode } = await import( '@wordpress/element' );
	const { dispatch } = await import( '@wordpress/data' );
	const { store: editorStore } = await import( '@wordpress/editor' );
	const { store: preferencesStore } = await import(
		'@wordpress/preferences'
	);
	const { registerCoreBlocks } = await import( '@wordpress/block-library' );

	return {
		createRoot,
		StrictMode,
		dispatch,
		editorStore,
		preferencesStore,
		registerCoreBlocks,
	};
}
