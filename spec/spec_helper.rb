# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'simplecov'

require_relative 'support/coverage_gate'

SimpleCov.start do
  enable_coverage :branch
  add_filter '/spec/'
  track_files 'lib/owl/**/*.rb'

  add_group 'Public API', %r{/api\.rb$}
  add_group 'Result',     %r{/result\.rb$}
  add_group 'Internal',   %r{/internal/}
end

SimpleCov.at_exit do
  SimpleCov.result.format!

  # The 100% public-API gate is only meaningful on a full-suite run; a partial
  # run loads only some api.rb/result.rb files and would falsely trip it.
  next unless CoverageGate.full_suite_run?(
    RSpec.configuration.files_to_run,
    Dir.glob('spec/**/*_spec.rb')
  )

  public_api_pattern = %r{/lib/owl/(.+/)?(api|result)\.rb\z}
  api_files = SimpleCov.result.files.select { |file| file.filename =~ public_api_pattern }
  uncovered = api_files.reject { |file| file.covered_percent >= 100.0 }

  next if uncovered.empty?

  warn ''
  warn 'Public API files below 100% line coverage:'
  uncovered.each do |file|
    warn "  #{file.filename}: #{file.covered_percent.round(2)}%"
  end
  exit 1
end

require_relative 'support/tmp_project'

require 'owl/internal/cache'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.warnings = true
  config.default_formatter = 'doc' if config.files_to_run.one?
  config.order = :random
  Kernel.srand config.seed

  config.before { Owl::Internal::Cache.clear! }
end
