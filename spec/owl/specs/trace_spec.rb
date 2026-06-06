# frozen_string_literal: true

require 'pathname'
require 'stringio'

require 'owl/cli/api'
require 'owl/specs/api'

RSpec.describe 'Owl::Specs::Api.trace' do
  def init_project(root)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: ['init', '--root', root.to_s], stdout: stdout, stderr: stderr, env: {}, cwd: root.to_s)
  end

  def seed_spec(root, domain, body)
    write("#{root}/specs/#{domain}/spec.md", body)
  end

  def traced_spec
    <<~MD
      ---
      status: active
      summary: Demo.
      ---

      # Spec

      ## Requirements

      ### Requirement: A
      The system SHALL do A.

      #### Scenario: One
      - WHEN x
      - THEN y
      - TEST: specs/demo/spec.md
    MD
  end

  def untraced_spec
    <<~MD
      ## Requirements

      ### Requirement: A
      The system SHALL do A.

      #### Scenario: No test
      - WHEN x
      - THEN y
    MD
  end

  it 'returns a valid, ok report for a fully-traced spec (ref resolves under root)' do
    with_tmp_project do |root|
      init_project(root)
      seed_spec(root, 'demo', traced_spec)
      result = Owl::Specs::Api.trace(root: root, domain: 'demo')
      expect(result).to be_ok
      expect(result.value[:valid]).to be(true)
      expect(result.value[:ok]).to be(true)
      expect(result.value[:domain]).to eq('demo')
      expect(result.value[:path]).to eq("#{root}/specs/demo/spec.md")
      expect(result.value[:summary][:traced]).to eq(1)
    end
  end

  it 'keeps ok true under non-strict but flips ok false under strict when untraced' do
    with_tmp_project do |root|
      init_project(root)
      seed_spec(root, 'demo', untraced_spec)

      lenient = Owl::Specs::Api.trace(root: root, domain: 'demo')
      expect(lenient.value[:valid]).to be(false)
      expect(lenient.value[:ok]).to be(true)

      strict = Owl::Specs::Api.trace(root: root, domain: 'demo', strict: true)
      expect(strict.value[:valid]).to be(false)
      expect(strict.value[:ok]).to be(false)
      expect(strict.value[:untraced]).to eq([{ requirement: 'A', scenario: 'No test' }])
    end
  end

  it 'reuses invalid_domain for an unsafe slug without touching the filesystem' do
    with_tmp_project do |root|
      init_project(root)
      result = Owl::Specs::Api.trace(root: root, domain: '../escape')
      expect(result).to be_err
      expect(result.code).to eq(:invalid_domain)
    end
  end

  it 'reuses spec_not_found for a missing domain' do
    with_tmp_project do |root|
      init_project(root)
      result = Owl::Specs::Api.trace(root: root, domain: 'ghost')
      expect(result).to be_err
      expect(result.code).to eq(:spec_not_found)
    end
  end

  it 'is read-only: tracing does not create or modify any file under specs/' do
    with_tmp_project do |root|
      init_project(root)
      path = seed_spec(root, 'demo', untraced_spec)
      before_mtime = path.mtime
      before_entries = Pathname.new("#{root}/specs").glob('**/*').map(&:to_s).sort

      Owl::Specs::Api.trace(root: root, domain: 'demo', strict: true)

      expect(path.read).to eq(untraced_spec)
      expect(path.mtime).to eq(before_mtime)
      expect(Pathname.new("#{root}/specs").glob('**/*').map(&:to_s).sort).to eq(before_entries)
    end
  end
end
