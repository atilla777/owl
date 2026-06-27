# frozen_string_literal: true

# Pure helper for the SimpleCov public-API coverage gate in `spec_helper.rb`.
#
# The gate enforces 100% line coverage on `lib/owl/**/{api,result}.rb`, but that
# check is only meaningful on a FULL suite run — a partial run
# (`rspec spec/owl/foo_spec.rb`) loads only some API files and would falsely
# report them under-covered. `full_suite_run?` decides whether the files RSpec
# is actually executing match the complete project spec set, so the gate can be
# silent on partial runs. It is a plain module method with no side effects (no
# `exit`, no `at_exit`) so it is unit-testable in isolation.
module CoverageGate
  module_function

  # @param files_to_run [Array<String>] paths RSpec is executing this run
  #   (typically `RSpec.configuration.files_to_run`).
  # @param all_spec_files [Array<String>] the full project spec set
  #   (typically `Dir.glob('spec/**/*_spec.rb')`).
  # @return [Boolean] true when the executed set equals the full set.
  def full_suite_run?(files_to_run, all_spec_files)
    normalize(files_to_run) == normalize(all_spec_files)
  end

  def normalize(paths)
    paths.map { |path| File.expand_path(path) }.uniq.sort
  end
end
