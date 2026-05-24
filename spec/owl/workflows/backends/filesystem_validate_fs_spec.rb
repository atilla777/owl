# frozen_string_literal: true

require 'owl/workflows/backends/filesystem'

RSpec.describe Owl::Workflows::Backends::Filesystem, '#validate filesystem refs' do
  def seed_workflow(root, body)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
          version: "1.0"
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", body)
  end

  def base_body
    <<~YAML
      id: feature
      kind: task
      title: Feature
      artifacts: {}
      steps:
        - id: main
          session_type: discussion
          context_file: main.md
    YAML
  end

  it 'returns ok when context_file exists on disk' do
    with_tmp_project do |root|
      seed_workflow(root, base_body)
      write("#{root}/.owl/workflows/feature/main.md", '# main')
      backend = described_class.new(root: root)
      result = backend.validate(id_or_path: 'feature')
      expect(result).to be_ok, -> { "expected ok, got #{result.details.inspect}" }
    end
  end

  it 'returns err with step_context_file_not_found when step context_file is missing' do
    with_tmp_project do |root|
      seed_workflow(root, base_body)
      # no main.md
      backend = described_class.new(root: root)
      result = backend.validate(id_or_path: 'feature')
      expect(result).to be_err
      errors = result.details[:errors]
      expect(errors.map { |e| e[:path] }).to include('/steps/0/context_file')
      codes = errors.map { |e| e[:code] }
      expect(codes).to include('step_context_file_not_found')
    end
  end

  it 'returns err for missing variant context_file with the variant-scoped path locator' do
    body = <<~YAML
      id: feature
      kind: task
      title: Feature
      artifacts: {}
      steps:
        - id: brief
          session_type: discussion
          default_variant: a
          variants:
            a:
              context_file: a.md
            b:
              context_file: b.md
    YAML
    with_tmp_project do |root|
      seed_workflow(root, body)
      write("#{root}/.owl/workflows/feature/a.md", '# a')
      # b.md missing
      backend = described_class.new(root: root)
      result = backend.validate(id_or_path: 'feature')
      expect(result).to be_err
      paths = result.details[:errors].map { |e| e[:path] }
      expect(paths).to include('/steps/0/variants/b/context_file')
      expect(paths).not_to include('/steps/0/variants/a/context_file')
    end
  end

  it 'returns err for context_file escaping the workflow source directory' do
    body = <<~YAML
      id: feature
      kind: task
      title: Feature
      artifacts: {}
      steps:
        - id: main
          session_type: discussion
          context_file: ../../../etc/passwd
    YAML
    with_tmp_project do |root|
      seed_workflow(root, body)
      backend = described_class.new(root: root)
      result = backend.validate(id_or_path: 'feature')
      expect(result).to be_err
      codes = result.details[:errors].map { |e| e[:code] }
      expect(codes).to include('step_context_path_escape')
    end
  end

  it 'returns err with duplicate variant key detection (raw YAML path)' do
    body = <<~YAML
      id: feature
      kind: task
      title: Feature
      artifacts: {}
      steps:
        - id: brief
          session_type: discussion
          default_variant: a
          variants:
            a:
              context_file: a.md
            a:
              context_file: b.md
    YAML
    with_tmp_project do |root|
      seed_workflow(root, body)
      write("#{root}/.owl/workflows/feature/a.md", '# a')
      write("#{root}/.owl/workflows/feature/b.md", '# b')
      backend = described_class.new(root: root)
      result = backend.validate(id_or_path: 'feature')
      expect(result).to be_err
      errors = result.details[:errors]
      expect(errors.map { |e| e[:path] }).to include('/steps/0/variants')
      expect(errors.first[:message]).to match(/Duplicate variant key 'a'/)
    end
  end
end
