/**
 * External dependencies
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

/**
 * Internal dependencies
 */
import {
	requestLatestContent,
	getPost,
	getNetworkProxy,
	showBlockInserter,
} from './bridge';

vi.mock( './logger.js', () => ( {
	error: vi.fn(),
	warn: vi.fn(),
	info: vi.fn(),
	debug: vi.fn(),
} ) );

describe( 'requestLatestContent', () => {
	let originalWindow;

	beforeEach( () => {
		// Store original window properties
		originalWindow = {
			webkit: window.webkit,
			editorDelegate: window.editorDelegate,
		};
		// Clear any existing bridge properties
		delete window.webkit;
		delete window.editorDelegate;
	} );

	afterEach( () => {
		// Restore original window properties
		if ( originalWindow.webkit !== undefined ) {
			window.webkit = originalWindow.webkit;
		}
		if ( originalWindow.editorDelegate !== undefined ) {
			window.editorDelegate = originalWindow.editorDelegate;
		}
	} );

	describe( 'iOS bridge', () => {
		it( 'should return parsed response from iOS handler', async () => {
			const mockContent = {
				title: 'Test Title',
				content: 'Test Content',
			};
			window.webkit = {
				messageHandlers: {
					requestLatestContent: {
						postMessage: vi.fn().mockResolvedValue( mockContent ),
					},
				},
			};

			const result = await requestLatestContent();

			expect( result ).toEqual( mockContent );
			expect(
				window.webkit.messageHandlers.requestLatestContent.postMessage
			).toHaveBeenCalledWith( {} );
		} );

		it( 'should return null when iOS handler rejects', async () => {
			window.webkit = {
				messageHandlers: {
					requestLatestContent: {
						postMessage: vi
							.fn()
							.mockRejectedValue( new Error( 'Handler error' ) ),
					},
				},
			};

			const result = await requestLatestContent();

			expect( result ).toBeNull();
		} );

		it( 'should return null when iOS handler returns null', async () => {
			window.webkit = {
				messageHandlers: {
					requestLatestContent: {
						postMessage: vi.fn().mockResolvedValue( null ),
					},
				},
			};

			const result = await requestLatestContent();

			expect( result ).toBeNull();
		} );
	} );

	describe( 'Android bridge', () => {
		it( 'should return parsed JSON from Android interface', async () => {
			const mockContent = {
				title: 'Test Title',
				content: 'Test Content',
			};
			window.editorDelegate = {
				requestLatestContent: vi
					.fn()
					.mockReturnValue( JSON.stringify( mockContent ) ),
			};

			const result = await requestLatestContent();

			expect( result ).toEqual( mockContent );
			expect(
				window.editorDelegate.requestLatestContent
			).toHaveBeenCalled();
		} );

		it( 'should return null when Android returns null', async () => {
			window.editorDelegate = {
				requestLatestContent: vi.fn().mockReturnValue( null ),
			};

			const result = await requestLatestContent();

			expect( result ).toBeNull();
		} );

		it( 'should return null when Android returns empty string', async () => {
			window.editorDelegate = {
				requestLatestContent: vi.fn().mockReturnValue( '' ),
			};

			const result = await requestLatestContent();

			expect( result ).toBeNull();
		} );

		it( 'should return null when Android returns malformed JSON', async () => {
			window.editorDelegate = {
				requestLatestContent: vi
					.fn()
					.mockReturnValue( 'not valid json' ),
			};

			const result = await requestLatestContent();

			expect( result ).toBeNull();
		} );

		it( 'should return null when Android method throws', async () => {
			window.editorDelegate = {
				requestLatestContent: vi.fn().mockImplementation( () => {
					throw new Error( 'Method error' );
				} ),
			};

			const result = await requestLatestContent();

			expect( result ).toBeNull();
		} );
	} );

	describe( 'no bridge available', () => {
		it( 'should return null when no bridge is available', async () => {
			// Neither window.webkit nor window.editorDelegate is set

			const result = await requestLatestContent();

			expect( result ).toBeNull();
		} );

		it( 'should return null when webkit exists but handler does not', async () => {
			window.webkit = {
				messageHandlers: {},
			};

			const result = await requestLatestContent();

			expect( result ).toBeNull();
		} );

		it( 'should return null when editorDelegate exists but method does not', async () => {
			window.editorDelegate = {};

			const result = await requestLatestContent();

			expect( result ).toBeNull();
		} );
	} );
} );

describe( 'getPost', () => {
	let originalWindow;

	beforeEach( () => {
		// Store original window properties
		originalWindow = {
			webkit: window.webkit,
			editorDelegate: window.editorDelegate,
			GBKit: window.GBKit,
		};
		// Clear any existing properties
		delete window.webkit;
		delete window.editorDelegate;
		delete window.GBKit;
	} );

	afterEach( () => {
		// Restore original window properties
		if ( originalWindow.webkit !== undefined ) {
			window.webkit = originalWindow.webkit;
		}
		if ( originalWindow.editorDelegate !== undefined ) {
			window.editorDelegate = originalWindow.editorDelegate;
		}
		if ( originalWindow.GBKit !== undefined ) {
			window.GBKit = originalWindow.GBKit;
		}
	} );

	describe( 'content from native host', () => {
		it( 'should return host content when available', async () => {
			const hostContent = {
				title: 'Host Title',
				content: 'Host Content',
			};
			window.webkit = {
				messageHandlers: {
					requestLatestContent: {
						postMessage: vi.fn().mockResolvedValue( hostContent ),
					},
				},
			};
			window.GBKit = {
				post: {
					id: 123,
					type: 'page',
					status: 'draft',
					title: 'GBKit%20Title',
					content: 'GBKit%20Content',
				},
			};

			const result = await getPost();

			expect( result ).toEqual( {
				id: 123,
				type: 'page',
				status: 'draft',
				title: { raw: 'Host Title' },
				content: { raw: 'Host Content' },
				restBase: 'posts',
				restNamespace: 'wp/v2',
			} );
		} );

		it( 'should use GBKit post metadata with host content', async () => {
			const hostContent = {
				title: 'Updated Title',
				content: 'Updated Content',
			};
			window.webkit = {
				messageHandlers: {
					requestLatestContent: {
						postMessage: vi.fn().mockResolvedValue( hostContent ),
					},
				},
			};
			window.GBKit = {
				post: {
					id: 456,
					type: 'post',
					status: 'publish',
					title: 'Original%20Title',
					content: 'Original%20Content',
				},
			};

			const result = await getPost();

			// Should use id/type/status from GBKit, but title/content from host
			expect( result.id ).toBe( 456 );
			expect( result.type ).toBe( 'post' );
			expect( result.status ).toBe( 'publish' );
			expect( result.title.raw ).toBe( 'Updated Title' );
			expect( result.content.raw ).toBe( 'Updated Content' );
		} );

		it( 'should coerce post ID 0 to -1 with host content', async () => {
			const hostContent = {
				title: 'Title',
				content: 'Content',
			};
			window.webkit = {
				messageHandlers: {
					requestLatestContent: {
						postMessage: vi.fn().mockResolvedValue( hostContent ),
					},
				},
			};
			window.GBKit = {
				post: {
					id: 0,
					type: 'post',
					status: 'draft',
					title: 'Title',
					content: 'Content',
				},
			};

			const result = await getPost();

			expect( result.id ).toBe( -1 );
		} );
	} );

	describe( 'fallback to GBKit', () => {
		it( 'should fall back to GBKit when host returns null', async () => {
			window.webkit = {
				messageHandlers: {
					requestLatestContent: {
						postMessage: vi.fn().mockResolvedValue( null ),
					},
				},
			};
			window.GBKit = {
				post: {
					id: 789,
					type: 'post',
					status: 'draft',
					title: 'GBKit%20Title',
					content: 'GBKit%20Content',
				},
			};

			const result = await getPost();

			expect( result ).toEqual( {
				id: 789,
				type: 'post',
				status: 'draft',
				title: { raw: 'GBKit Title' },
				content: { raw: 'GBKit Content' },
				restBase: 'posts',
				restNamespace: 'wp/v2',
			} );
		} );

		it( 'should fall back to GBKit when no bridge available', async () => {
			// No bridge set up
			window.GBKit = {
				post: {
					id: 101,
					type: 'page',
					status: 'publish',
					title: 'Fallback%20Title',
					content: 'Fallback%20Content',
				},
			};

			const result = await getPost();

			expect( result ).toEqual( {
				id: 101,
				type: 'page',
				status: 'publish',
				title: { raw: 'Fallback Title' },
				content: { raw: 'Fallback Content' },
				restBase: 'posts',
				restNamespace: 'wp/v2',
			} );
		} );

		it( 'should coerce post ID 0 to -1 in GBKit fallback', async () => {
			window.GBKit = {
				post: {
					id: 0,
					type: 'post',
					status: 'draft',
					title: 'Title',
					content: 'Content',
				},
			};

			const result = await getPost();

			expect( result.id ).toBe( -1 );
		} );
	} );

	describe( 'default empty post', () => {
		it( 'should return default empty post when both are unavailable', async () => {
			// No bridge and no GBKit

			const result = await getPost();

			expect( result ).toEqual( {
				id: -1,
				type: 'post',
				status: 'draft',
				title: { raw: '' },
				content: { raw: '' },
				restBase: 'posts',
				restNamespace: 'wp/v2',
			} );
		} );

		it( 'should use defaults when GBKit post lacks optional fields', async () => {
			const hostContent = {
				title: 'Title',
				content: 'Content',
			};
			window.webkit = {
				messageHandlers: {
					requestLatestContent: {
						postMessage: vi.fn().mockResolvedValue( hostContent ),
					},
				},
			};
			// GBKit exists but post is empty/undefined
			window.GBKit = {};

			const result = await getPost();

			expect( result ).toEqual( {
				id: -1,
				type: 'post',
				status: 'draft',
				title: { raw: 'Title' },
				content: { raw: 'Content' },
				restBase: 'posts',
				restNamespace: 'wp/v2',
			} );
		} );
	} );
} );

describe( 'showBlockInserter', () => {
	let originalWindow;

	const sampleInserter = {
		sections: [
			{
				name: 'text',
				title: 'Text',
				blockTypes: [
					{
						id: 'core/paragraph',
						name: 'core/paragraph',
						title: 'Paragraph',
					},
				],
			},
		],
		patterns: [],
		patternCategories: [],
	};

	beforeEach( () => {
		originalWindow = {
			webkit: window.webkit,
			editorDelegate: window.editorDelegate,
			blockInserter: window.blockInserter,
		};
		delete window.webkit;
		delete window.editorDelegate;
		delete window.blockInserter;
	} );

	afterEach( () => {
		if ( originalWindow.webkit !== undefined ) {
			window.webkit = originalWindow.webkit;
		}
		if ( originalWindow.editorDelegate !== undefined ) {
			window.editorDelegate = originalWindow.editorDelegate;
		}
		if ( originalWindow.blockInserter !== undefined ) {
			window.blockInserter = originalWindow.blockInserter;
		}
	} );

	it( 'is a no-op when window.blockInserter is unavailable', () => {
		const editorDelegate = { showBlockInserter: vi.fn() };
		window.editorDelegate = editorDelegate;

		showBlockInserter( { x: 0, y: 0, width: 10, height: 10 } );

		expect( editorDelegate.showBlockInserter ).not.toHaveBeenCalled();
	} );

	it( 'passes a JSON-stringified payload to the Android bridge', () => {
		window.blockInserter = sampleInserter;
		const editorDelegate = { showBlockInserter: vi.fn() };
		window.editorDelegate = editorDelegate;

		const sourceRect = { x: 1, y: 2, width: 3, height: 4 };
		showBlockInserter( sourceRect );

		expect( editorDelegate.showBlockInserter ).toHaveBeenCalledTimes( 1 );
		const arg = editorDelegate.showBlockInserter.mock.calls[ 0 ][ 0 ];
		expect( typeof arg ).toBe( 'string' );
		expect( JSON.parse( arg ) ).toEqual( {
			sections: sampleInserter.sections,
			patterns: sampleInserter.patterns,
			patternCategories: sampleInserter.patternCategories,
			sourceRect,
		} );
	} );

	it( 'passes a structured payload to the iOS bridge', () => {
		window.blockInserter = sampleInserter;
		const postMessage = vi.fn();
		window.webkit = {
			messageHandlers: {
				editorDelegate: { postMessage },
			},
		};

		const sourceRect = { x: 1, y: 2, width: 3, height: 4 };
		showBlockInserter( sourceRect );

		expect( postMessage ).toHaveBeenCalledTimes( 1 );
		expect( postMessage ).toHaveBeenCalledWith( {
			message: 'showBlockInserter',
			body: {
				sections: sampleInserter.sections,
				patterns: sampleInserter.patterns,
				patternCategories: sampleInserter.patternCategories,
				sourceRect,
			},
		} );
	} );

	it( 'dispatches to both bridges when both are present', () => {
		window.blockInserter = sampleInserter;
		const editorDelegate = { showBlockInserter: vi.fn() };
		const postMessage = vi.fn();
		window.editorDelegate = editorDelegate;
		window.webkit = {
			messageHandlers: {
				editorDelegate: { postMessage },
			},
		};

		showBlockInserter();

		expect( editorDelegate.showBlockInserter ).toHaveBeenCalledTimes( 1 );
		expect( postMessage ).toHaveBeenCalledTimes( 1 );
	} );
} );

describe( 'getNetworkProxy', () => {
	afterEach( () => {
		delete window.GBKit;
		localStorage.clear();
	} );

	it( 'returns the injected relay details', () => {
		window.GBKit = { networkProxy: { port: 5555, token: 'fresh' } };

		expect( getNetworkProxy() ).toEqual( { port: 5555, token: 'fresh' } );
	} );

	it( 'returns null when the host is not running a relay', () => {
		window.GBKit = { siteApiRoot: 'https://example.com/wp-json/' };

		expect( getNetworkProxy() ).toBeNull();
	} );

	it( 'ignores a persisted relay from an earlier session', () => {
		// A relay's port and token belong to the server that issued them, and
		// iOS never clears `GBKit` from localStorage. Trusting a persisted copy
		// would point every REST request at a stopped listener — or at a port
		// something else now owns.
		localStorage.setItem(
			'GBKit',
			JSON.stringify( { networkProxy: { port: 4444, token: 'stale' } } )
		);

		expect( getNetworkProxy() ).toBeNull();
	} );
} );
