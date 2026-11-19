import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
	requestLatestContent,
	getGBKit,
	getPost,
	getPostPath,
	getPostReference,
	showBlockInserter,
	onEditorSaveAvailabilityChanged,
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
		/**
		 * Stands in for the object Android's web message listener injects. Each
		 * reply `respond` returns for a posted request arrives as a `message`
		 * event, as native code's replies do.
		 *
		 * @param {(request: Object) => Array<Object|string>} respond Returns the replies to a parsed request.
		 * @return {Object} The fake `window.editorDelegate`.
		 */
		function fakeAndroidDelegate( respond ) {
			const target = new EventTarget();
			return {
				postMessage: vi.fn( ( json ) => {
					for ( const response of respond( JSON.parse( json ) ) ) {
						const data =
							typeof response === 'string'
								? response
								: JSON.stringify( response );
						queueMicrotask( () =>
							target.dispatchEvent(
								new MessageEvent( 'message', { data } )
							)
						);
					}
				} ),
				addEventListener: vi.fn(
					target.addEventListener.bind( target )
				),
				removeEventListener: vi.fn(
					target.removeEventListener.bind( target )
				),
			};
		}

		function reply( request, result ) {
			return {
				message: 'requestLatestContent',
				body: { id: request.body.id, result },
			};
		}

		it( "should return the host's content from its reply", async () => {
			const mockContent = {
				title: 'Test Title',
				content: 'Test Content',
			};
			window.editorDelegate = fakeAndroidDelegate( ( request ) => [
				reply( request, mockContent ),
			] );

			const result = await requestLatestContent();

			expect( result ).toEqual( mockContent );
			const request = JSON.parse(
				window.editorDelegate.postMessage.mock.calls[ 0 ][ 0 ]
			);
			expect( request ).toEqual( {
				message: 'requestLatestContent',
				body: { id: expect.any( Number ) },
			} );
		} );

		it( 'should return null when the host has no content', async () => {
			window.editorDelegate = fakeAndroidDelegate( ( request ) => [
				reply( request, null ),
			] );

			const result = await requestLatestContent();

			expect( result ).toBeNull();
		} );

		it( 'should ignore messages that are not its reply', async () => {
			const mockContent = { title: 'Mine', content: 'Mine' };
			window.editorDelegate = fakeAndroidDelegate( ( request ) => [
				'not valid json',
				{ message: 'somethingElse', body: { id: request.body.id } },
				{
					message: 'requestLatestContent',
					body: { id: request.body.id + 1, result: {} },
				},
				reply( request, mockContent ),
			] );

			const result = await requestLatestContent();

			expect( result ).toEqual( mockContent );
		} );

		it( 'should stop listening once it has its reply', async () => {
			window.editorDelegate = fakeAndroidDelegate( ( request ) => [
				reply( request, null ),
			] );

			await requestLatestContent();

			const listener =
				window.editorDelegate.addEventListener.mock.calls[ 0 ][ 1 ];
			expect(
				window.editorDelegate.removeEventListener
			).toHaveBeenCalledWith( 'message', listener );
		} );

		it( 'should return null when posting the request throws', async () => {
			window.editorDelegate = fakeAndroidDelegate( () => {
				throw new Error( 'Post error' );
			} );

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
	} );
} );

describe( 'getGBKit', () => {
	let originalGBKit;

	beforeEach( () => {
		originalGBKit = window.GBKit;
		delete window.GBKit;
		localStorage.clear();
	} );

	afterEach( () => {
		if ( originalGBKit !== undefined ) {
			window.GBKit = originalGBKit;
		} else {
			delete window.GBKit;
		}
		localStorage.clear();
	} );

	it( 'returns the injected global', () => {
		window.GBKit = { siteApiRoot: 'https://example.com/wp-json/' };

		expect( getGBKit() ).toEqual( {
			siteApiRoot: 'https://example.com/wp-json/',
		} );
	} );

	it( 'ignores a configuration persisted by an earlier session', () => {
		// The configuration carries the site credential and the local server's
		// port and token, none of which outlive the load that injected them.
		localStorage.setItem(
			'GBKit',
			JSON.stringify( {
				siteApiRoot: 'https://stale.example.com/wp-json/',
				authHeader: 'Bearer stale',
			} )
		);

		expect( getGBKit() ).toEqual( {} );
	} );
} );

describe( 'getPostReference', () => {
	it( "returns the host's post identifiers", () => {
		expect(
			getPostReference( {
				id: 5,
				type: 'book',
				restBase: 'books',
				restNamespace: 'library/v1',
				title: 'Title',
			} )
		).toEqual( {
			id: 5,
			type: 'book',
			restBase: 'books',
			restNamespace: 'library/v1',
		} );
	} );

	it( 'falls back for fields the host omits', () => {
		expect( getPostReference( { id: 5 } ) ).toEqual( {
			id: 5,
			type: 'post',
			restBase: 'posts',
			restNamespace: 'wp/v2',
		} );
		expect( getPostReference() ).toEqual( {
			id: -1,
			type: 'post',
			restBase: 'posts',
			restNamespace: 'wp/v2',
		} );
	} );
} );

describe( 'getPostPath', () => {
	it( "returns the post's REST path", () => {
		expect(
			getPostPath( {
				id: 5,
				restBase: 'books',
				restNamespace: 'library/v1',
			} )
		).toBe( '/library/v1/books/5' );
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

		it( 'should seed a post without a server ID as an auto-draft', async () => {
			window.webkit = {
				messageHandlers: {
					requestLatestContent: {
						postMessage: vi
							.fn()
							.mockResolvedValue( { title: '', content: '' } ),
					},
				},
			};
			window.GBKit = {
				post: { id: -1, type: 'post', status: 'draft' },
			};

			const result = await getPost();

			expect( result.status ).toBe( 'auto-draft' );
		} );

		it( "should keep the host's status for a local draft with a title", async () => {
			window.webkit = {
				messageHandlers: {
					requestLatestContent: {
						postMessage: vi.fn().mockResolvedValue( {
							title: 'Trip notes',
							content: '',
						} ),
					},
				},
			};
			window.GBKit = {
				post: { id: -1, type: 'post', status: 'draft' },
			};

			const result = await getPost();

			expect( result.status ).toBe( 'draft' );
		} );

		it( "should keep the host's status for a local draft with content", async () => {
			window.webkit = {
				messageHandlers: {
					requestLatestContent: {
						postMessage: vi.fn().mockResolvedValue( {
							title: '',
							content: '<p>Day 1</p>',
						} ),
					},
				},
			};
			window.GBKit = {
				post: { id: -1, type: 'post', status: 'draft' },
			};

			const result = await getPost();

			expect( result.status ).toBe( 'draft' );
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
			expect( result.status ).toBe( 'draft' );
		} );

		it( 'should seed an empty post without a server ID as an auto-draft', async () => {
			window.GBKit = {
				post: {
					id: -1,
					type: 'post',
					status: 'draft',
					title: '',
					content: '',
				},
			};

			const result = await getPost();

			expect( result.status ).toBe( 'auto-draft' );
		} );
	} );

	describe( 'default empty post', () => {
		it( 'should return default empty post when both are unavailable', async () => {
			// No bridge and no GBKit

			const result = await getPost();

			expect( result ).toEqual( {
				id: -1,
				type: 'post',
				status: 'auto-draft',
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
		const editorDelegate = { postMessage: vi.fn() };
		window.editorDelegate = editorDelegate;

		showBlockInserter( { x: 0, y: 0, width: 10, height: 10 } );

		expect( editorDelegate.postMessage ).not.toHaveBeenCalled();
	} );

	it( 'passes a JSON-stringified message to the Android bridge', () => {
		window.blockInserter = sampleInserter;
		const editorDelegate = { postMessage: vi.fn() };
		window.editorDelegate = editorDelegate;

		const sourceRect = { x: 1, y: 2, width: 3, height: 4 };
		showBlockInserter( sourceRect );

		expect( editorDelegate.postMessage ).toHaveBeenCalledTimes( 1 );
		const arg = editorDelegate.postMessage.mock.calls[ 0 ][ 0 ];
		expect( typeof arg ).toBe( 'string' );
		expect( JSON.parse( arg ) ).toEqual( {
			message: 'showBlockInserter',
			body: {
				sections: sampleInserter.sections,
				patterns: sampleInserter.patterns,
				patternCategories: sampleInserter.patternCategories,
				sourceRect,
			},
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
		const editorDelegate = { postMessage: vi.fn() };
		const postMessage = vi.fn();
		window.editorDelegate = editorDelegate;
		window.webkit = {
			messageHandlers: {
				editorDelegate: { postMessage },
			},
		};

		showBlockInserter();

		expect( editorDelegate.postMessage ).toHaveBeenCalledTimes( 1 );
		expect( postMessage ).toHaveBeenCalledTimes( 1 );
	} );
} );

describe( 'onEditorSaveAvailabilityChanged', () => {
	let originalWindow;

	beforeEach( () => {
		originalWindow = {
			webkit: window.webkit,
			editorDelegate: window.editorDelegate,
		};
		delete window.webkit;
		delete window.editorDelegate;
	} );

	afterEach( () => {
		if ( originalWindow.webkit !== undefined ) {
			window.webkit = originalWindow.webkit;
		}
		if ( originalWindow.editorDelegate !== undefined ) {
			window.editorDelegate = originalWindow.editorDelegate;
		}
	} );

	// `GutenbergView` reads these keys on Android.
	it( 'passes a keyed message to the Android bridge', () => {
		const editorDelegate = { postMessage: vi.fn() };
		window.editorDelegate = editorDelegate;

		onEditorSaveAvailabilityChanged( true, false );

		expect(
			JSON.parse( editorDelegate.postMessage.mock.calls[ 0 ][ 0 ] )
		).toEqual( {
			message: 'onEditorSaveAvailabilityChanged',
			body: { isSaveable: true, isSavingLocked: false },
		} );
	} );

	// `EditorSaveAvailability` decodes these keys on iOS.
	it( 'passes a keyed payload to the iOS bridge', () => {
		const postMessage = vi.fn();
		window.webkit = {
			messageHandlers: {
				editorDelegate: { postMessage },
			},
		};

		onEditorSaveAvailabilityChanged( false, true );

		expect( postMessage ).toHaveBeenCalledWith( {
			message: 'onEditorSaveAvailabilityChanged',
			body: { isSaveable: false, isSavingLocked: true },
		} );
	} );
} );
