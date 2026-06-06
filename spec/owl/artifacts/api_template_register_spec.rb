# frozen_string_literal: true

require 'yaml'
require 'owl/artifacts/api'

RSpec.describe Owl::Artifacts::Api, '.template_show / .template_set / .register' do
  def seed_project(root)
    write("#{root}/.owl/artifacts.yaml", Owl::Artifacts::Api.default_template)
    Owl::Artifacts::Api.seeded_sources.each do |source|
      write("#{root}/#{source[:relative_path]}", source[:contents])
    end
  end

  describe '.scaffold with from:' do
    it 'clones an existing type body and template' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.scaffold(root: root, id: 'my_plan', from: 'plan')
        expect(result).to be_ok
        parsed = YAML.safe_load_file("#{root}/.owl/artifacts/my_plan/artifact.yaml")
        expect(parsed['id']).to eq('my_plan')
        # template cloned from the source type, not the minimal stub
        cloned = File.read("#{root}/.owl/artifacts/my_plan/templates/default.md")
        original = File.read("#{root}/.owl/artifacts/plan/templates/default.md")
        expect(cloned).to eq(original)
      end
    end

    it 'errors when the source type to clone from is unknown' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.scaffold(root: root, id: 'x_plan', from: 'nope')
        expect(result).to be_err
        expect(result.code).to eq(:unknown_artifact_type)
      end
    end
  end

  describe '.template_show' do
    it 'returns the template body for a registered type' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.template_show(root: root, id: 'plan')
        expect(result).to be_ok
        expect(result.value[:body]).to include('## Goal')
      end
    end

    it 'returns artifact_template_missing when the template file is absent' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.template_show(root: root, id: 'plan', template: 'nope')
        expect(result).to be_err
        expect(result.code).to eq(:artifact_template_missing)
      end
    end
  end

  describe '.template_set' do
    it 'refuses to write a managed (Owl-shipped) type' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.template_set(root: root, id: 'plan', body: '## Goal')
        expect(result).to be_err
        expect(result.code).to eq(:artifact_type_managed)
      end
    end

    it 'writes the template of a project-owned (cloned + registered) type' do
      with_tmp_project do |root|
        seed_project(root)
        described_class.scaffold(root: root, id: 'mine', from: 'plan')
        described_class.register(root: root, id: 'mine', managed: false)
        result = described_class.template_set(root: root, id: 'mine', body: "## Goal\nx\n")
        expect(result).to be_ok
        expect(File.read("#{root}/.owl/artifacts/mine/templates/default.md")).to include('## Goal')
      end
    end

    it 'writes the template of an unregistered type (project-owned by absence)' do
      with_tmp_project do |root|
        seed_project(root)
        described_class.scaffold(root: root, id: 'loose', from: 'plan')
        result = described_class.template_set(root: root, id: 'loose', body: '## Goal', template: 'strict')
        expect(result).to be_ok
        expect(File.exist?("#{root}/.owl/artifacts/loose/templates/strict.md")).to be(true)
      end
    end
  end

  describe '.template_validate' do
    it 'validates a satisfied template body, ignoring placeholders' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.template_validate(root: root, id: 'plan')
        expect(result).to be_ok
        expect(result.value[:valid]).to be(true)
      end
    end

    it 'reports violations when required sections are missing' do
      with_tmp_project do |root|
        seed_project(root)
        described_class.scaffold(root: root, id: 'thin', from: 'plan')
        described_class.template_set(root: root, id: 'thin', body: "# Nothing here\n")
        result = described_class.template_validate(root: root, id: 'thin')
        expect(result).to be_ok
        expect(result.value[:valid]).to be(false)
        expect(result.value[:violations]).not_to be_empty
      end
    end
  end

  describe '.register / .unregister' do
    it 'registers a project-owned type by default' do
      with_tmp_project do |root|
        seed_project(root)
        described_class.scaffold(root: root, id: 'reg_me', from: 'plan')
        result = described_class.register(root: root, id: 'reg_me')
        expect(result).to be_ok
        raw = YAML.safe_load_file("#{root}/.owl/artifacts.yaml")
        expect(raw.dig('artifacts', 'reg_me', 'managed')).to be(false)
      end
    end

    it 'refuses to re-register without force, then overwrites with force' do
      with_tmp_project do |root|
        seed_project(root)
        described_class.register(root: root, id: 'twice')
        again = described_class.register(root: root, id: 'twice')
        expect(again).to be_err
        expect(again.code).to eq(:artifact_type_already_registered)
        forced = described_class.register(root: root, id: 'twice', managed: true, force: true)
        expect(forced).to be_ok
        raw = YAML.safe_load_file("#{root}/.owl/artifacts.yaml")
        expect(raw.dig('artifacts', 'twice', 'managed')).to be(true)
      end
    end

    it 'unregisters an existing entry' do
      with_tmp_project do |root|
        seed_project(root)
        described_class.register(root: root, id: 'drop_me')
        result = described_class.unregister(root: root, id: 'drop_me')
        expect(result).to be_ok
        raw = YAML.safe_load_file("#{root}/.owl/artifacts.yaml")
        expect(raw['artifacts']).not_to have_key('drop_me')
      end
    end

    it 'errors when unregistering a type that is not registered' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.unregister(root: root, id: 'ghost')
        expect(result).to be_err
        expect(result.code).to eq(:artifact_type_not_registered)
      end
    end

    it 'errors when the registry file is missing' do
      with_tmp_project do |root|
        result = described_class.register(root: root, id: 'orphan')
        expect(result).to be_err
        expect(result.code).to eq(:artifacts_registry_missing)
      end
    end
  end
end
