/**
 * External dependencies
 */
import '@testing-library/jest-dom/vitest';
import { afterEach } from 'vitest';
import { cleanup } from '@testing-library/react';

// Mirror Jest's auto-cleanup behavior
// https://testing-library.com/docs/react-testing-library/setup#auto-cleanup-in-vitest
afterEach( cleanup );
