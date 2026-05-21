# frozen_string_literal: true

require_relative 'lib/owl/version'

Gem::Specification.new do |spec|
  spec.name        = 'owl-cli'
  spec.version     = Owl::VERSION
  spec.authors     = ['Aleksei Slivka']
  spec.email       = ['slivka77@outlook.com']

  spec.summary     = 'CLI for AI-assisted, spec-driven development workflows.'
  spec.description = <<~DESC
    Owl is a personal CLI that lets AI agents drive software work through
    typed, declarative workflows. It manages tasks, workflow state,
    artifacts, and the publishing pipeline that turns task-local specs
    into durable domain documentation. Agents talk to Owl via the `owl`
    CLI and a small set of seeded skills rather than touching project
    files directly.
  DESC

  spec.required_ruby_version = '>= 3.3'

  spec.bindir      = 'bin'
  spec.executables = ['owl']
  spec.require_paths = ['lib']

  spec.files = Dir[
    'lib/**/*.rb',
    'bin/owl',
    'skills/**/*',
    'commands/**/*.md',
    'workflows/**/*',
    'artifacts/**/*',
    'schemas/**/*.json',
    'README.md'
  ]

  spec.metadata = {
    'rubygems_mfa_required' => 'true'
  }
end
