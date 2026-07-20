/**
 * External dependencies
 */
import { defineConfig, devices } from '@playwright/test';

const isCI = process.env.CI === 'true';

// CI uses production build, local development uses dev server
const url = isCI ? 'http://localhost:4173' : 'http://localhost:5173';

export default defineConfig( {
	testDir: './e2e',
	// Narrower than the default, which also claims `*.test.js` — those belong to
	// Vitest, which covers the non-spec helpers in this directory.
	testMatch: '**/*.spec.js',
	outputDir: './e2e/test-results',
	fullyParallel: true,
	workers: isCI ? 1 : undefined,
	retries: isCI ? 2 : 0,
	timeout: 60_000,
	reporter: isCI ? 'list' : 'html',
	use: {
		baseURL: url,
		actionTimeout: 10_000,
		trace: 'on-first-retry',
	},
	projects: [
		{
			name: 'chromium',
			use: { ...devices[ 'Desktop Chrome' ] },
		},
	],
	webServer: {
		// CI uses production build, local development uses dev server
		command: isCI ? 'npm run preview' : 'npm run dev',
		url,
		reuseExistingServer: ! isCI,
		timeout: 30_000,
	},
} );
