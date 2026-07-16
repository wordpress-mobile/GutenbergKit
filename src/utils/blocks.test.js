/**
 * External dependencies
 */
import { describe, it, expect, vi } from 'vitest';
import Ajv from 'ajv';

/**
 * Internal dependencies
 */
import {
	preprocessBlockTypesForNativeInserter,
	formatPatternsForNativeInserter,
	formatPatternCategoriesForNativeInserter,
} from './blocks';
import blockInserterPayloadSchema from '../../schemas/block-inserter-payload.schema.json';

vi.mock( './logger.js', () => ( {
	error: vi.fn(),
	warn: vi.fn(),
	info: vi.fn(),
	debug: vi.fn(),
} ) );

// `src/utils/blocks.js` pulls in `@wordpress/blocks` and `@wordpress/element`.
// Neither is needed for the pure transforms under test here, and loading the
// real packages in vitest trips on JSON import attributes.
vi.mock( '@wordpress/blocks', () => ( {
	unregisterBlockType: vi.fn(),
	getBlockTypes: vi.fn( () => [] ),
} ) );
vi.mock( '@wordpress/element', () => ( {
	renderToString: vi.fn( () => '' ),
} ) );

const validate = new Ajv().compile( blockInserterPayloadSchema );

function assertBlockInserterPayloadShape( payload ) {
	if ( validate( payload ) ) {
		return;
	}
	const { instancePath, dataPath, message } = validate.errors[ 0 ];
	throw new Error( `${ instancePath || dataPath || '/' }: ${ message }` );
}

function makeInserterItem( overrides = {} ) {
	return {
		id: 'core/paragraph',
		name: 'core/paragraph',
		title: 'Paragraph',
		description: 'Start with the basic building block of all narrative.',
		category: 'text',
		keywords: [ 'text' ],
		icon: '<svg></svg>',
		frecency: 0,
		isDisabled: false,
		isSearchOnly: false,
		parent: [],
		...overrides,
	};
}

const WP_CATEGORIES = [
	{ slug: 'text', title: 'Text' },
	{ slug: 'media', title: 'Media' },
	{ slug: 'design', title: 'Design' },
];

describe( 'preprocessBlockTypesForNativeInserter', () => {
	it( 'returns sections whose blocks conform to the BlockType shape', () => {
		const sections = preprocessBlockTypesForNativeInserter(
			[
				makeInserterItem(),
				makeInserterItem( {
					id: 'core/image',
					name: 'core/image',
					title: 'Image',
					category: 'media',
					keywords: [],
				} ),
			],
			null,
			WP_CATEGORIES
		);

		expect( sections.length ).toBeGreaterThan( 0 );
		expect( () =>
			assertBlockInserterPayloadShape( {
				sections,
				patterns: [],
				patternCategories: [],
			} )
		).not.toThrow();
	} );

	it( 'routes contextual blocks into a gbk-contextual section', () => {
		const sections = preprocessBlockTypesForNativeInserter(
			[
				makeInserterItem( {
					id: 'core/column',
					name: 'core/column',
					title: 'Column',
					category: 'design',
					parent: [ 'core/columns' ],
				} ),
			],
			'core/columns',
			WP_CATEGORIES
		);

		const contextual = sections.find(
			( s ) => s.category === 'gbk-contextual'
		);
		expect( contextual ).toBeDefined();
		expect( contextual.name ).toBeNull();
		expect( contextual.blocks.map( ( b ) => b.id ) ).toEqual( [
			'core/column',
		] );
	} );

	it( 'splits search-only blocks into a hidden gbk-search-only section', () => {
		const sections = preprocessBlockTypesForNativeInserter(
			[
				makeInserterItem(),
				makeInserterItem( {
					id: 'core/heading/h2',
					name: 'core/heading',
					title: 'Heading (H2)',
					isSearchOnly: true,
				} ),
			],
			null,
			WP_CATEGORIES
		);

		const searchOnly = sections.find(
			( s ) => s.category === 'gbk-search-only'
		);
		expect( searchOnly ).toBeDefined();
		expect( searchOnly.blocks.map( ( b ) => b.id ) ).toEqual( [
			'core/heading/h2',
		] );
	} );

	it( 'defaults keywords and parents to arrays, not null', () => {
		const sections = preprocessBlockTypesForNativeInserter(
			[
				makeInserterItem( {
					keywords: undefined,
					parent: undefined,
				} ),
			],
			null,
			WP_CATEGORIES
		);

		const block = sections[ 0 ].blocks[ 0 ];
		expect( Array.isArray( block.keywords ) ).toBe( true );
		expect( Array.isArray( block.parents ) ).toBe( true );
	} );
} );

describe( 'formatPatternsForNativeInserter', () => {
	it( 'returns an empty array for null or undefined input', () => {
		expect( formatPatternsForNativeInserter( null ) ).toEqual( [] );
		expect( formatPatternsForNativeInserter( undefined ) ).toEqual( [] );
	} );

	it( 'fills missing arrays with [], not null', () => {
		const [ pattern ] = formatPatternsForNativeInserter( [
			{ name: 'p', title: 'T', content: '' },
		] );

		expect( pattern.blockTypes ).toEqual( [] );
		expect( pattern.categories ).toEqual( [] );
		expect( pattern.keywords ).toEqual( [] );
	} );

	it( 'preserves nullable scalar fields as null when absent', () => {
		const [ pattern ] = formatPatternsForNativeInserter( [
			{ name: 'p', title: 'T', content: '' },
		] );

		expect( pattern.description ).toBeNull();
		expect( pattern.source ).toBeNull();
		expect( pattern.viewportWidth ).toBeNull();
	} );

	it( 'filters underscore-prefixed categories', () => {
		const [ pattern ] = formatPatternsForNativeInserter( [
			{
				name: 'p',
				title: 'T',
				content: '',
				categories: [ 'gallery', '_internal', 'query' ],
			},
		] );

		expect( pattern.categories ).toEqual( [ 'gallery', 'query' ] );
	} );

	it( 'drops non-string categories without throwing', () => {
		// User/synced patterns can momentarily expose raw numeric term IDs
		// (instead of slug strings) while core-data resolves the id→slug
		// lookup table. Those must not reach `startsWith`.
		expect( () =>
			formatPatternsForNativeInserter( [
				{
					name: 'core/block/42',
					title: 'Synced',
					content: '',
					categories: [ 'gallery', 7, '_internal', null ],
				},
			] )
		).not.toThrow();

		const [ pattern ] = formatPatternsForNativeInserter( [
			{
				name: 'core/block/42',
				title: 'Synced',
				content: '',
				categories: [ 'gallery', 7, '_internal', null ],
			},
		] );

		expect( pattern.categories ).toEqual( [ 'gallery' ] );
	} );

	it( 'produces patterns that conform to the Pattern shape', () => {
		const patterns = formatPatternsForNativeInserter( [
			{
				name: 'core/query-standard-posts',
				title: 'Standard Posts',
				content: '<!-- wp:query --><!-- /wp:query -->',
				blockTypes: [ 'core/query' ],
				categories: [ 'query', '_internal' ],
				description: 'Standard posts query',
				keywords: [ 'posts' ],
				source: 'pattern-directory',
				viewportWidth: 1200,
			},
			{ name: 'minimal', title: 'Minimal', content: '' },
		] );

		expect( () =>
			assertBlockInserterPayloadShape( {
				sections: [],
				patterns,
				patternCategories: [],
			} )
		).not.toThrow();
	} );
} );

describe( 'formatPatternCategoriesForNativeInserter', () => {
	it( 'returns an empty array for null or undefined input', () => {
		expect( formatPatternCategoriesForNativeInserter( null ) ).toEqual(
			[]
		);
		expect( formatPatternCategoriesForNativeInserter( undefined ) ).toEqual(
			[]
		);
	} );

	it( 'produces categories that conform to the PatternCategory shape', () => {
		const categories = formatPatternCategoriesForNativeInserter( [
			{ name: 'gallery', label: 'Gallery', extra: 'ignored' },
		] );

		expect( categories ).toEqual( [
			{ name: 'gallery', label: 'Gallery' },
		] );
		expect( () =>
			assertBlockInserterPayloadShape( {
				sections: [],
				patterns: [],
				patternCategories: categories,
			} )
		).not.toThrow();
	} );
} );

describe( 'assertBlockInserterPayloadShape', () => {
	// Self-tests for the shape checker. These guard against false negatives
	// (the checker missing real drift) and false positives (rejecting valid
	// payloads). If these fail, the checker is broken, not the producers.

	it( 'accepts a payload assembled from the real formatters', () => {
		const payload = {
			sections: preprocessBlockTypesForNativeInserter(
				[ makeInserterItem() ],
				null,
				WP_CATEGORIES
			),
			patterns: formatPatternsForNativeInserter( [
				{
					name: 'core/query',
					title: 'Query',
					content: '<!-- wp:query /-->',
				},
			] ),
			patternCategories: formatPatternCategoriesForNativeInserter( [
				{ name: 'gallery', label: 'Gallery' },
			] ),
			sourceRect: { x: 10, y: 20, width: 30, height: 40 },
		};

		expect( () =>
			assertBlockInserterPayloadShape( payload )
		).not.toThrow();
	} );

	it( 'accepts a payload without a sourceRect', () => {
		const payload = {
			sections: [],
			patterns: [],
			patternCategories: [],
		};

		expect( () =>
			assertBlockInserterPayloadShape( payload )
		).not.toThrow();
	} );

	it( 'rejects a pattern with a null array field', () => {
		const payload = {
			sections: [],
			patterns: [
				{
					name: 'p',
					title: 'T',
					content: '',
					blockTypes: null,
					categories: [],
					description: null,
					keywords: [],
					source: null,
					viewportWidth: null,
				},
			],
			patternCategories: [],
		};

		expect( () => assertBlockInserterPayloadShape( payload ) ).toThrow(
			/blockTypes/
		);
	} );

	it( 'rejects a block type with a non-string id', () => {
		const payload = {
			sections: [
				{
					category: 'text',
					name: 'Text',
					blocks: [
						{
							id: 123,
							name: 'core/paragraph',
							keywords: [],
							frecency: 0,
							isDisabled: false,
							isSearchOnly: false,
							parents: [],
						},
					],
				},
			],
			patterns: [],
			patternCategories: [],
		};

		expect( () => assertBlockInserterPayloadShape( payload ) ).toThrow(
			/id/
		);
	} );

	it( 'rejects a payload with an unknown top-level field', () => {
		const payload = {
			sections: [],
			patterns: [],
			patternCategories: [],
			unexpectedField: 'leak',
		};

		expect( () => assertBlockInserterPayloadShape( payload ) ).toThrow(
			/additional/i
		);
	} );

	it( 'rejects a pattern with an unknown field', () => {
		const payload = {
			sections: [],
			patterns: [
				{
					name: 'p',
					title: 'T',
					content: '',
					blockTypes: [],
					categories: [],
					description: null,
					keywords: [],
					source: null,
					viewportWidth: null,
					leakedField: 'oops',
				},
			],
			patternCategories: [],
		};

		expect( () => assertBlockInserterPayloadShape( payload ) ).toThrow(
			/additional/i
		);
	} );
} );
