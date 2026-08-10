/**
 * Internal dependencies
 */
import { version as gbkVersion } from '../../package.json';
import { chromeStackParser, geckoStackParser } from './stack-parsers';

// The stack trace is limited to prevent crash logging service fail processing the exception.
const STACKTRACE_LIMIT = 50;

const stackParsers = [ chromeStackParser, geckoStackParser ];

// Based on function `createStackParser` and `parseStackFrames` of Sentry JavaScript SDK:
// - https://github.com/getsentry/sentry-javascript/blob/de681dcf7d6dac69da9374bbdbe2e2f7e00f0fdc/packages/utils/src/stacktrace.ts#L16-L59
// - https://github.com/getsentry/sentry-javascript/blob/de681dcf7d6dac69da9374bbdbe2e2f7e00f0fdc/packages/browser/src/eventbuilder.ts#L100-L118
// And function `stripSentryFramesAndReverse` of Sentry React Native SDK:
// https://github.com/getsentry/sentry-javascript/blob/de681dcf7d6dac69da9374bbdbe2e2f7e00f0fdc/packages/utils/src/stacktrace.ts#L80-L117
const parseStacktrace = ( exception ) => {
	const plainStacktrace = exception.stacktrace || exception.stack || '';
	const frames = [];
	const lines = plainStacktrace.split( '\n' );

	for ( let i = 0; i < lines.length; i++ ) {
		const line = lines[ i ];
		// Ignore lines over 1kb as they are unlikely to be valid frames.
		if ( line.length > 1024 ) {
			continue;
		}

		// Skip error message lines.
		if ( line.match( /\S*Error: / ) ) {
			continue;
		}

		for ( const parser of stackParsers ) {
			const entry = parser( line );

			if ( entry ) {
				frames.push( entry );
				break;
			}
		}

		if ( frames.length >= STACKTRACE_LIMIT ) {
			break;
		}
	}

	const reverseFrames = Array.from( frames ).reverse();

	return reverseFrames.slice( 0, STACKTRACE_LIMIT ).map( ( entry ) => ( {
		...entry,
		filename:
			entry.filename ||
			reverseFrames[ reverseFrames.length - 1 ].filename,
	} ) );
};

// Based on function `extractMessage` of Sentry JavaScript SDK:
// https://github.com/getsentry/sentry-javascript/blob/de681dcf7d6dac69da9374bbdbe2e2f7e00f0fdc/packages/browser/src/eventbuilder.ts#L142-L151
const extractMessage = ( exception ) => {
	const message = exception?.message;
	if ( ! message ) {
		return 'No error message';
	}
	if ( typeof message.error?.message === 'string' ) {
		return message.error.message;
	}
	return message;
};

// Based on function `exceptionFromError` of Sentry JavaScript SDK:
// https://github.com/getsentry/sentry-javascript/blob/de681dcf7d6dac69da9374bbdbe2e2f7e00f0fdc/packages/browser/src/eventbuilder.ts#L31-L49
const parseException = ( originalException ) => {
	const exception = {
		type: originalException?.name,
		message: extractMessage( originalException ),
	};

	exception.stacktrace = parseStacktrace( originalException );

	if ( exception.type === undefined && exception.message === '' ) {
		exception.message = 'Unknown error';
	}

	return exception;
};

// Build a map of `filename -> debugId` from the `window._sentryDebugIds` global.
// `sentry-cli sourcemaps inject` adds a snippet to each built chunk that captures
// its own `(new Error).stack` as a key and stores the chunk's Debug ID as the
// value. The top frame of that stack identifies the chunk's file, so parsing each
// key yields which Debug ID belongs to which file.
const getDebugIdsByFilename = () => {
	const debugIdMap =
		typeof window !== 'undefined' ? window._sentryDebugIds : undefined;
	if ( ! debugIdMap ) {
		return {};
	}

	const result = {};
	for ( const stack of Object.keys( debugIdMap ) ) {
		for ( const line of stack.split( '\n' ) ) {
			let frame;
			for ( const parser of stackParsers ) {
				frame = parser( line );
				if ( frame ) {
					break;
				}
			}
			// The first parseable frame's file is the chunk the snippet ran in.
			if ( frame?.filename ) {
				result[ frame.filename ] = debugIdMap[ stack ];
				break;
			}
		}
	}
	return result;
};

// Produce the Sentry `debug_meta` images for the files referenced by this
// exception's stack, so Sentry can match the uploaded source maps by Debug ID
// (independent of the unstable on-device file paths).
const getDebugImages = ( stacktrace ) => {
	const debugIdsByFilename = getDebugIdsByFilename();
	const seen = new Set();
	const images = [];

	for ( const frame of stacktrace ) {
		const filename = frame.filename;
		const debugId = filename && debugIdsByFilename[ filename ];
		if ( debugId && ! seen.has( filename ) ) {
			seen.add( filename );
			images.push( { code_file: filename, debug_id: debugId } );
		}
	}
	return images;
};

export default ( exception, { context, tags } = {} ) => {
	const parsed = parseException( exception );
	return {
		...parsed,
		debug_images: getDebugImages( parsed.stacktrace ),
		context: {
			...context,
		},
		tags: {
			...tags,
			gutenberg_kit_version: gbkVersion,
		},
	};
};
