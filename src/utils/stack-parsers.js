// Copyright (c) 2012 Functional Software, Inc. dba Sentry
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of
// this software and associated documentation files (the "Software"), to deal in
// the Software without restriction, including without limitation the rights to
// use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is furnished to do
// so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

const UNKNOWN_FUNCTION = '?';

function createFrame(filename, func, lineno, colno) {
	const frame = {
		filename,
		function: func === '<anonymous>' ? UNKNOWN_FUNCTION : func,
		in_app: true, // All browser frames are considered in_app
	};

	if (lineno !== undefined) {
		frame.lineno = lineno;
	}

	if (colno !== undefined) {
		frame.colno = colno;
	}

	return frame;
}

// This regex matches frames that have no function name (ie. are at the top level of a module).
// For example "at http://localhost:5000//script.js:1:126"
// Frames _with_ function names usually look as follows: "at commitLayoutEffects (react-dom.development.js:23426:1)"
const chromeRegexNoFnName = /^\s*at (\S+?)(?::(\d+))(?::(\d+))\s*$/i;

// This regex matches all the frames that have a function name.
const chromeRegex =
	/^\s*at (?:(.+?\)(?: \[.+\])?|.*?) ?\((?:address at )?)?(?:async )?((?:<anonymous>|[-a-z]+:|.*bundle|\/)?.*?)(?::(\d+))?(?::(\d+))?\)?\s*$/i;

const chromeEvalRegex = /\((\S*)(?::(\d+))(?::(\d+))\)/;

// Chromium based browsers: Chrome, Brave, new Opera, new Edge
// We cannot call this variable `chrome` because it can conflict with global `chrome` variable in certain environments
// See: https://github.com/getsentry/sentry-javascript/issues/6880
export const chromeStackParser = (line) => {
	// If the stack line has no function name, we need to parse it differently
	const noFnParts = chromeRegexNoFnName.exec(line);

	if (noFnParts) {
		const [, filename, _line, col] = noFnParts;
		return createFrame(filename, UNKNOWN_FUNCTION, +_line, +col);
	}

	const parts = chromeRegex.exec(line);

	if (parts) {
		const isEval = parts[2] && parts[2].indexOf('eval') === 0; // start of line

		if (isEval) {
			const subMatch = chromeEvalRegex.exec(parts[2]);

			if (subMatch) {
				// throw out eval line/column and use top-most line/column number
				parts[2] = subMatch[1]; // url
				parts[3] = subMatch[2]; // line
				parts[4] = subMatch[3]; // column
			}
		}

		const func = parts[1] || UNKNOWN_FUNCTION;
		const filename = parts[2];

		return createFrame(
			filename,
			func,
			parts[3] ? +parts[3] : undefined,
			parts[4] ? +parts[4] : undefined
		);
	}
};

// gecko regex: `(?:bundle|\d+\.js)`: `bundle` is for react native, `\d+\.js` also but specifically for ram bundles because it
// generates filenames without a prefix like `file://` the filenames in the stacktrace are just 42.js
// We need this specific case for now because we want no other regex to match.
const geckoREgex =
	/^\s*(.*?)(?:\((.*?)\))?(?:^|@)?((?:[-a-z]+)?:\/.*?|\[native code\]|[^@]*(?:bundle|\d+\.js)|\/[\w\-. /=]+)(?::(\d+))?(?::(\d+))?\s*$/i;
const geckoEvalRegex = /(\S+) line (\d+)(?: > eval line \d+)* > eval/i;

export const geckoStackParser = (line) => {
	const parts = geckoREgex.exec(line);

	if (parts) {
		const isEval = parts[3] && parts[3].indexOf(' > eval') > -1;
		if (isEval) {
			const subMatch = geckoEvalRegex.exec(parts[3]);

			if (subMatch) {
				// throw out eval line/column and use top-most line number
				parts[1] = parts[1] || 'eval';
				parts[3] = subMatch[1];
				parts[4] = subMatch[2];
				parts[5] = ''; // no column when eval
			}
		}

		const filename = parts[3];
		const func = parts[1] || UNKNOWN_FUNCTION;

		return createFrame(
			filename,
			func,
			parts[4] ? +parts[4] : undefined,
			parts[5] ? +parts[5] : undefined
		);
	}
};
