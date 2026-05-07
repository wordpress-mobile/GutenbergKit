# frozen_string_literal: true

source 'https://rubygems.org'

gem 'fastlane', '~> 2.230'
gem 'fastlane-plugin-wpmreleasetoolkit', '~> 13.8'

# Pinned to pull in the fix for GHSA-c4rq-3m3g-8wgx (CSS selector ReDoS).
# Drop once `fastlane-plugin-wpmreleasetoolkit` moves to >= 14.4.1, whose
# gemspec carries this floor transitively.
gem 'nokogiri', '>= 1.19.3'
