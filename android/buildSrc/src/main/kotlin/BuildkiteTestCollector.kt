/**
 * Register the Buildkite Test Engine listener for instrumented tests.
 *
 * On CI (detected via `BUILDKITE_BUILD_ID`), [tokenEnvName] is required —
 * a missing or blank token fails configuration rather than silently
 * producing a green build that uploaded nothing. Locally (no Buildkite
 * env), a missing token is a no-op and the collector is inert.
 *
 * Pass `testInstrumentationRunnerArguments` from AGP's `defaultConfig` as
 * [args]. Taking the map directly (rather than an AGP-typed receiver) keeps
 * `buildSrc` free of an AGP dependency, which avoids a plugin-classpath
 * conflict with each module's `alias(libs.plugins.android.*)` application.
 *
 * https://github.com/buildkite/test-collector-android/blob/main/CI_CONFIGURATION.md#buildkite
 */
fun configureBuildkiteTestCollector(
    args: MutableMap<String, String>,
    tokenEnvName: String,
) {
    val token = System.getenv(tokenEnvName)?.takeIf { it.isNotBlank() }
    val onBuildkite = !System.getenv("BUILDKITE_BUILD_ID").isNullOrBlank()

    if (token == null) {
        check(!onBuildkite) {
            "$tokenEnvName is required on Buildkite but was missing or blank. " +
                "Without it, the Test Engine collector is inert and the suite " +
                "silently receives no data."
        }
        return
    }

    args["listener"] = "com.buildkite.test.collector.android.InstrumentedTestCollector"
    args["BUILDKITE_ANALYTICS_TOKEN"] = token
    args["BUILDKITE_ANALYTICS_DEBUG_ENABLED"] = "true"

    listOf(
        "BUILDKITE_BUILD_ID",
        "BUILDKITE_BUILD_URL",
        "BUILDKITE_BRANCH",
        "BUILDKITE_COMMIT",
        "BUILDKITE_BUILD_NUMBER",
        "BUILDKITE_JOB_ID",
        "BUILDKITE_MESSAGE",
    ).forEach { key ->
        System.getenv(key)?.let { value -> args[key] = value }
    }
}
