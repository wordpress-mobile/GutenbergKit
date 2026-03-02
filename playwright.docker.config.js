/**
 * Playwright configuration for running tests inside Docker.
 *
 * This config is used by `make test-e2e-docker` which:
 * 1. Starts the preview server on the host
 * 2. Runs Playwright inside a Docker container
 * 3. Uses host.docker.internal to access host services
 *
 * Key differences from the standard config:
 * - No webServer (preview server runs on host, not in container)
 * - BASE_URL from environment (points to host.docker.internal)
 */

/**
 * External dependencies
 */
import { defineConfig, devices } from '@playwright/test';

export default defineConfig( {
	testDir: './e2e',
	outputDir: './e2e/test-results',
	fullyParallel: true,
	workers: 1,
	retries: 2,
	timeout: 60_000,
	reporter: 'list',
	use: {
		baseURL: process.env.BASE_URL || 'http://host.docker.internal:4173',
		actionTimeout: 10_000,
		trace: 'on-first-retry',
	},
	projects: [
		{
			name: 'chromium',
			use: { ...devices[ 'Desktop Chrome' ] },
		},
	],
	// No webServer - the preview server is started on the host by make test-e2e-docker
} );
