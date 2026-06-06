# frozen_string_literal: true

require 'yaml'
require 'owl/workflows/api'
require 'owl/artifacts/api'

RSpec.describe Owl::Workflows::Api, '.source_show / .context_show / .register' do
  def seed_project(root)
    write("#{root}/.owl/workflows.yaml", Owl::Workflows::Api.default_template)
    Owl::Workflows::Api.seeded_sources.each do |source|
      write("#{root}/#{source[:relative_path]}", source[:contents])
    end
    # feature/composite workflows reference artifact types, which the workflow
    # validator resolves against the artifact registry — so seed those too.
    write("#{root}/.owl/artifacts.yaml", Owl::Artifacts::Api.default_template)
    Owl::Artifacts::Api.seeded_sources.each do |source|
      write("#{root}/#{source[:relative_path]}", source[:contents])
    end
  end

  describe '.source_show' do
    it 'returns the raw workflow.yaml body' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.source_show(root: root, id: 'feature')
        expect(result).to be_ok
        expect(result.value[:body]).to include('id: feature')
      end
    end

    it 'errors for an unknown workflow' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.source_show(root: root, id: 'nope')
        expect(result).to be_err
        expect(result.code).to eq(:unknown_workflow)
      end
    end
  end

  describe '.context_show' do
    it 'reads a plain step context_file' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.context_show(root: root, id: 'feature', step_id: 'design')
        expect(result).to be_ok
        expect(result.value[:body]).not_to be_empty
      end
    end

    it 'reads a variant step context_file' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.context_show(root: root, id: 'feature', step_id: 'brief',
                                              variant: 'problem_inventory')
        expect(result).to be_ok
        expect(result.value[:body]).not_to be_empty
      end
    end

    it 'errors for an unknown step' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.context_show(root: root, id: 'feature', step_id: 'ghost')
        expect(result).to be_err
        expect(result.code).to eq(:unknown_step)
      end
    end
  end

  describe '.context_set' do
    it 'refuses to write a managed workflow' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.context_set(root: root, id: 'feature', step_id: 'design', body: 'x')
        expect(result).to be_err
        expect(result.code).to eq(:workflow_managed)
      end
    end

    it 'writes a step context for a project-owned (cloned) workflow' do
      with_tmp_project do |root|
        seed_project(root)
        described_class.scaffold(root: root, id: 'mine', from: 'feature')
        described_class.register(root: root, id: 'mine', managed: false)
        result = described_class.context_set(root: root, id: 'mine', step_id: 'design', body: "new\n")
        expect(result).to be_ok
        expect(described_class.context_show(root: root, id: 'mine', step_id: 'design').value[:body]).to eq("new\n")
      end
    end

    it 'errors when the step declares no context_file' do
      with_tmp_project do |root|
        seed_project(root)
        write("#{root}/.owl/workflows.yaml", <<~YAML)
          schema_version: 1
          workflows:
            bare:
              source: "workflows/bare/workflow.yaml"
              managed: false
        YAML
        write("#{root}/.owl/workflows/bare/workflow.yaml", <<~YAML)
          id: bare
          kind: task
          artifacts: {}
          steps:
            - id: solo
              session_type: discussion
        YAML
        result = described_class.context_set(root: root, id: 'bare', step_id: 'solo', body: 'x')
        expect(result).to be_err
        expect(result.code).to eq(:step_context_file_undeclared)
      end
    end
  end

  describe '.register / .unregister' do
    it 'registers a project-owned workflow by default' do
      with_tmp_project do |root|
        seed_project(root)
        described_class.scaffold(root: root, id: 'reg_flow', from: 'feature')
        result = described_class.register(root: root, id: 'reg_flow', title: 'Reg Flow')
        expect(result).to be_ok
        raw = YAML.safe_load_file("#{root}/.owl/workflows.yaml")
        expect(raw.dig('workflows', 'reg_flow', 'managed')).to be(false)
        expect(raw.dig('workflows', 'reg_flow', 'title')).to eq('Reg Flow')
      end
    end

    it 'refuses to re-register without force' do
      with_tmp_project do |root|
        seed_project(root)
        described_class.register(root: root, id: 'dup_flow')
        again = described_class.register(root: root, id: 'dup_flow')
        expect(again).to be_err
        expect(again.code).to eq(:workflow_already_registered)
      end
    end

    it 'unregisters an existing entry' do
      with_tmp_project do |root|
        seed_project(root)
        described_class.register(root: root, id: 'temp_flow')
        result = described_class.unregister(root: root, id: 'temp_flow')
        expect(result).to be_ok
        raw = YAML.safe_load_file("#{root}/.owl/workflows.yaml")
        expect(raw['workflows']).not_to have_key('temp_flow')
      end
    end

    it 'errors when unregistering a non-registered workflow' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.unregister(root: root, id: 'ghost')
        expect(result).to be_err
        expect(result.code).to eq(:workflow_not_registered)
      end
    end

    it 'errors when the registry file is missing' do
      with_tmp_project do |root|
        result = described_class.register(root: root, id: 'orphan')
        expect(result).to be_err
        expect(result.code).to eq(:workflows_registry_missing)
      end
    end
  end
end
