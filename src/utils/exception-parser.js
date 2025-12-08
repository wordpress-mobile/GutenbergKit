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

export default ( exception, { context, tags } = {} ) => {
	return {
		...parseException( exception ),
		context: {
			...context,
		},
		tags: {
			...tags,
			gutenberg_kit_version: gbkVersion,
		},
	};
};
