# frozen_string_literal: true

require 'yaml'
require 'owl/workflows/api'
require 'owl/artifacts/api'

RSpec.describe Owl::Workflows::Api, '.scaffold and .validate' do
  def seed_project(root)
    write("#{root}/.owl/workflows.yaml", Owl::Workflows::Api.default_template)
    write("#{root}/.owl/artifacts.yaml", Owl::Artifacts::Api.default_template)
    Owl::Artifacts::Api.seeded_sources.each do |source|
      write("#{root}/#{source[:relative_path]}", source[:contents])
    end
    Owl::Workflows::Api.seeded_sources.each do |source|
      write("#{root}/#{source[:relative_path]}", source[:contents])
    end
  end

  def workflow_source_path(root, id)
    described_class.local_paths(root: root, key: id).value.source_path
  end

  describe '.scaffold' do
    it 'writes the seeded task minimal seed when no body is supplied' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.scaffold(root: root, id: 'sample', kind: 'task')
        expect(result).to be_ok
        path = workflow_source_path(root, 'sample')
        expect(File.exist?(path)).to be(true)
        parsed = YAML.safe_load_file(path)
        expect(parsed['id']).to eq('sample')
        expect(parsed['kind']).to eq('task')
        expect(parsed['steps'].first['id']).to eq('main')
      end
    end

    it 'writes the composite_task seed when kind is composite_task' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.scaffold(root: root, id: 'sample_c', kind: 'composite_task')
        expect(result).to be_ok
        parsed = YAML.safe_load_file(workflow_source_path(root, 'sample_c'))
        expect(parsed['kind']).to eq('composite_task')
        expect(parsed['artifacts']).to include('decomposition')
      end
    end

    it 'refuses to overwrite an existing source without force' do
      with_tmp_project do |root|
        seed_project(root)
        described_class.scaffold(root: root, id: 'dup', kind: 'task')
        retry_result = described_class.scaffold(root: root, id: 'dup', kind: 'task')
        expect(retry_result).to be_err
        expect(retry_result.code).to eq(:workflow_already_exists)
      end
    end

    it 'overwrites with force' do
      with_tmp_project do |root|
        seed_project(root)
        described_class.scaffold(root: root, id: 'over', kind: 'task')
        result = described_class.scaffold(root: root, id: 'over', kind: 'composite_task', force: true)
        expect(result).to be_ok
        parsed = YAML.safe_load_file(workflow_source_path(root, 'over'))
        expect(parsed['kind']).to eq('composite_task')
      end
    end

    it 'accepts a custom body and validates it before write' do
      with_tmp_project do |root|
        seed_project(root)
        body = "id: custom_id\nkind: task\ntitle: Custom\nartifacts: {}\n" \
               "steps:\n  - id: only\n    skill: owl-step-discussion\n    session_type: discussion\n"
        result = described_class.scaffold(root: root, id: 'custom_id', body: body)
        expect(result).to be_ok
      end
    end

    it 'rejects an invalid body without creating the file' do
      with_tmp_project do |root|
        seed_project(root)
        body = "id: bad\nkind: task\nsteps:\n  - skill: owl-step-run\n"
        result = described_class.scaffold(root: root, id: 'bad', body: body)
        expect(result).to be_err
        expect(result.code).to eq(:workflow_validation_failed)
        expect(File.exist?("#{root}/.owl/workflows/bad/workflow.yaml")).to be(false)
      end
    end

    it 'rejects an invalid id' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.scaffold(root: root, id: 'Bad-Id', kind: 'task')
        expect(result).to be_err
        expect(result.code).to eq(:invalid_workflow_id)
      end
    end

    it 'clones from an existing workflow when --from is given' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.scaffold(root: root, id: 'cloned', from: 'feature')
        expect(result).to be_ok
        cloned = YAML.safe_load_file(workflow_source_path(root, 'cloned'))
        expect(cloned['id']).to eq('cloned')
        expect(cloned['steps'].size).to be > 1
      end
    end

    it 'reports workflow_source_missing when --from points to a registered workflow with no source file' do
      with_tmp_project do |root|
        seed_project(root)
        File.delete("#{root}/.owl/workflows/feature/workflow.yaml")
        result = described_class.scaffold(root: root, id: 'noop_clone', from: 'feature')
        expect(result).to be_err
        expect(result.code).to eq(:workflow_source_missing)
      end
    end
  end

  describe '.validate' do
    it 'validates a registered workflow by id' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.validate(root: root, id_or_path: 'feature')
        expect(result).to be_ok
        expect(result.value[:valid]).to be(true)
      end
    end

    it 'validates a fresh definition by absolute path' do
      with_tmp_project do |root|
        seed_project(root)
        described_class.scaffold(root: root, id: 'fresh', kind: 'task')
        result = described_class.validate(root: root, id_or_path: workflow_source_path(root, 'fresh'))
        expect(result).to be_ok
        expect(result.value[:valid]).to be(true)
      end
    end

    it 'returns workflow_validation_failed for a malformed YAML on disk' do
      with_tmp_project do |root|
        seed_project(root)
        bad_path = "#{root}/.owl/workflows/oops/workflow.yaml"
        write(bad_path, "id: oops\nkind: task\nsteps:\n  - skill: owl-step-discussion\n    session_type: discussion\n")
        result = described_class.validate(root: root, id_or_path: bad_path)
        expect(result).to be_err
        expect(result.code).to eq(:workflow_validation_failed)
      end
    end

    it 'returns workflow_source_missing when the file path does not exist' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.validate(root: root, id_or_path: "#{root}/missing/workflow.yaml")
        expect(result).to be_err
        expect(result.code).to eq(:workflow_source_missing)
      end
    end

    it 'returns unknown_workflow for an unregistered id' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.validate(root: root, id_or_path: 'nope')
        expect(result).to be_err
        expect(result.code).to eq(:unknown_workflow)
      end
    end

    it 'reports workflow_validation_failed when the YAML root is not a mapping' do
      with_tmp_project do |root|
        seed_project(root)
        bad_path = "#{root}/.owl/workflows/list_root/workflow.yaml"
        write(bad_path, "- a\n- b\n")
        result = described_class.validate(root: root, id_or_path: bad_path)
        expect(result).to be_err
        expect(result.code).to eq(:workflow_validation_failed)
      end
    end

    it 'reports workflow_validation_failed on malformed YAML syntax' do
      with_tmp_project do |root|
        seed_project(root)
        bad_path = "#{root}/.owl/workflows/syntax_err/workflow.yaml"
        write(bad_path, ': : :')
        result = described_class.validate(root: root, id_or_path: bad_path)
        expect(result).to be_err
        expect(result.code).to eq(:workflow_validation_failed)
      end
    end

    it 'reports workflow_source_missing when a registered workflow body is unreadable' do
      with_tmp_project do |root|
        seed_project(root)
        File.write("#{root}/.owl/workflows/feature/workflow.yaml", "- 1\n- 2\n")
        result = described_class.validate(root: root, id_or_path: 'feature')
        expect(result).to be_err
        expect(result.code).to eq(:workflow_source_missing)
      end
    end

    describe 'step variants' do
      it 'accepts a step with `variants` and a matching `default_variant`' do
        with_tmp_project do |root|
          seed_project(root)
          body = <<~YAML
            id: variant_ok
            kind: task
            title: V
            artifacts: {}
            steps:
              - id: brief
                skill: owl-step-discussion
                session_type: discussion
                default_variant: feature
                variants:
                  feature:
                    context_file: brief.feature.context.md
                  root_cause:
                    context_file: brief.root_cause.context.md
          YAML
          result = described_class.scaffold(root: root, id: 'variant_ok', body: body)
          expect(result).to be_ok
        end
      end

      it 'rejects `variants` without `default_variant`' do
        with_tmp_project do |root|
          seed_project(root)
          body = <<~YAML
            id: no_default
            kind: task
            artifacts: {}
            steps:
              - id: brief
                skill: owl-step-discussion
                session_type: discussion
                variants:
                  feature:
                    context_file: brief.feature.context.md
          YAML
          result = described_class.scaffold(root: root, id: 'no_default', body: body)
          expect(result).to be_err
          expect(result.code).to eq(:workflow_validation_failed)
          messages = result.details[:errors].map { |e| e[:message] }
          expect(messages.join("\n")).to match(/default_variant.*required/)
        end
      end

      it 'rejects `default_variant` that is not a key in `variants`' do
        with_tmp_project do |root|
          seed_project(root)
          body = <<~YAML
            id: ghost_default
            kind: task
            artifacts: {}
            steps:
              - id: brief
                skill: owl-step-discussion
                session_type: discussion
                default_variant: missing
                variants:
                  feature:
                    context_file: brief.feature.context.md
          YAML
          result = described_class.scaffold(root: root, id: 'ghost_default', body: body)
          expect(result).to be_err
          expect(result.code).to eq(:workflow_validation_failed)
          messages = result.details[:errors].map { |e| e[:message] }
          expect(messages.join("\n")).to match(/not a key in `variants`/)
        end
      end

      it 'rejects `default_variant` without `variants`' do
        with_tmp_project do |root|
          seed_project(root)
          body = <<~YAML
            id: orphan_default
            kind: task
            artifacts: {}
            steps:
              - id: brief
                skill: owl-step-discussion
                session_type: discussion
                default_variant: feature
          YAML
          result = described_class.scaffold(root: root, id: 'orphan_default', body: body)
          expect(result).to be_err
          expect(result.code).to eq(:workflow_validation_failed)
          messages = result.details[:errors].map { |e| e[:message] }
          expect(messages.join("\n")).to match(/default_variant.*requires a `variants:`/)
        end
      end

      it 'rejects mixing `variants` with step-level `context_file`' do
        with_tmp_project do |root|
          seed_project(root)
          body = <<~YAML
            id: mixed
            kind: task
            artifacts: {}
            steps:
              - id: brief
                skill: owl-step-discussion
                session_type: discussion
                context_file: brief.context.md
                default_variant: feature
                variants:
                  feature:
                    context_file: brief.feature.context.md
          YAML
          result = described_class.scaffold(root: root, id: 'mixed', body: body)
          expect(result).to be_err
          expect(result.code).to eq(:workflow_validation_failed)
          messages = result.details[:errors].map { |e| e[:message] }
          expect(messages.join("\n")).to match(/variants.*mutually exclusive/)
        end
      end

      it 'rejects a variant missing `context_file`' do
        with_tmp_project do |root|
          seed_project(root)
          body = <<~YAML
            id: no_cf
            kind: task
            artifacts: {}
            steps:
              - id: brief
                skill: owl-step-discussion
                session_type: discussion
                default_variant: feature
                variants:
                  feature: {}
          YAML
          result = described_class.scaffold(root: root, id: 'no_cf', body: body)
          expect(result).to be_err
          expect(result.code).to eq(:workflow_validation_failed)
        end
      end
    end
  end
end
