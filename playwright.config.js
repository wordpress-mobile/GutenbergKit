/**
 * External dependencies
 */
import { defineConfig, devices } from '@playwright/test';

export default defineConfig( {
	testDir: './e2e',
	outputDir: './e2e/test-results',
	fullyParallel: false,
	workers: 1,
	retries: process.env.CI ? 2 : 0,
	timeout: 60_000,
	reporter: process.env.CI ? 'list' : 'html',
	use: {
		baseURL: 'http://localhost:4173',
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
		command: 'npm run preview',
		url: 'http://localhost:4173',
		reuseExistingServer: true,
		timeout: 30_000,
	},
} );
