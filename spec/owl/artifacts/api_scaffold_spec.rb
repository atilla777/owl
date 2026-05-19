# frozen_string_literal: true

require 'yaml'
require 'owl/artifacts/api'

RSpec.describe Owl::Artifacts::Api, '.scaffold and .validate' do
  def seed_project(root)
    write("#{root}/.owl/artifacts.yaml", Owl::Artifacts::Api.default_template)
    Owl::Artifacts::Api.seeded_sources.each do |source|
      write("#{root}/#{source[:relative_path]}", source[:contents])
    end
  end

  describe '.scaffold' do
    it 'writes the minimal seed when no body is supplied' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.scaffold(root: root, id: 'sample')
        expect(result).to be_ok
        parsed = YAML.safe_load_file(result.value[:path])
        expect(parsed['id']).to eq('sample')
        expect(parsed['title']).to eq('sample')
        expect(parsed['kind']).to eq('markdown')
        expect(parsed.dig('front_matter', 'required')).to eq(%w[status summary])
        expect(parsed.dig('validation', 'required_sections')).to eq(['Summary'])
        expect(File.exist?(result.value[:template_path])).to be(true)
      end
    end

    it 'refuses to overwrite an existing source without force' do
      with_tmp_project do |root|
        seed_project(root)
        described_class.scaffold(root: root, id: 'dup_at')
        retry_result = described_class.scaffold(root: root, id: 'dup_at')
        expect(retry_result).to be_err
        expect(retry_result.code).to eq(:artifact_type_already_exists)
      end
    end

    it 'overwrites with force' do
      with_tmp_project do |root|
        seed_project(root)
        described_class.scaffold(root: root, id: 'over_at')
        body = "id: over_at\ntitle: Forced\nkind: markdown\nvalidation:\n  required_sections: [Summary]\n"
        result = described_class.scaffold(root: root, id: 'over_at', body: body, force: true)
        expect(result).to be_ok
        parsed = YAML.safe_load_file(result.value[:path])
        expect(parsed['title']).to eq('Forced')
      end
    end

    it 'rejects an invalid id' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.scaffold(root: root, id: 'Bad-Id')
        expect(result).to be_err
        expect(result.code).to eq(:invalid_artifact_type_id)
      end
    end

    it 'rejects an invalid body without creating the file' do
      with_tmp_project do |root|
        seed_project(root)
        body = "title: NoId\nkind: markdown\n"
        result = described_class.scaffold(root: root, id: 'noid_at', body: body)
        expect(result).to be_err
        expect(result.code).to eq(:artifact_type_validation_failed)
        expect(File.exist?("#{root}/.owl/artifacts/noid_at/artifact.yaml")).to be(false)
      end
    end
  end

  describe '.validate' do
    it 'validates a registered artifact type by id' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.validate(root: root, id_or_path: 'brief')
        expect(result).to be_ok
        expect(result.value[:valid]).to be(true)
      end
    end

    it 'validates a fresh artifact-type by path' do
      with_tmp_project do |root|
        seed_project(root)
        scaffold = described_class.scaffold(root: root, id: 'fresh_at')
        result = described_class.validate(root: root, id_or_path: scaffold.value[:path])
        expect(result).to be_ok
        expect(result.value[:valid]).to be(true)
      end
    end

    it 'returns artifact_type_validation_failed for a malformed body on disk' do
      with_tmp_project do |root|
        seed_project(root)
        bad_path = "#{root}/.owl/artifacts/oops_at/artifact.yaml"
        write(bad_path, "title: NoId\nkind: markdown\n")
        result = described_class.validate(root: root, id_or_path: bad_path)
        expect(result).to be_err
        expect(result.code).to eq(:artifact_type_validation_failed)
      end
    end

    it 'returns artifact_type_source_missing when the path does not exist' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.validate(root: root, id_or_path: "#{root}/missing.yaml")
        expect(result).to be_err
        expect(result.code).to eq(:artifact_type_source_missing)
      end
    end

    it 'returns unknown_artifact_type for an unregistered id' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.validate(root: root, id_or_path: 'nope_at')
        expect(result).to be_err
        expect(result.code).to eq(:unknown_artifact_type)
      end
    end

    it 'reports artifact_type_validation_failed when the YAML root is not a mapping' do
      with_tmp_project do |root|
        seed_project(root)
        bad_path = "#{root}/.owl/artifacts/list_root/artifact.yaml"
        write(bad_path, "- a\n- b\n")
        result = described_class.validate(root: root, id_or_path: bad_path)
        expect(result).to be_err
        expect(result.code).to eq(:artifact_type_validation_failed)
      end
    end

    it 'reports artifact_type_validation_failed on malformed YAML' do
      with_tmp_project do |root|
        seed_project(root)
        bad_path = "#{root}/.owl/artifacts/syntax_err/artifact.yaml"
        write(bad_path, ': : :')
        result = described_class.validate(root: root, id_or_path: bad_path)
        expect(result).to be_err
        expect(result.code).to eq(:artifact_type_validation_failed)
      end
    end

    it 'reports artifact_type_validation_failed when a registered source body is not a mapping' do
      with_tmp_project do |root|
        seed_project(root)
        broken_source = "#{root}/.owl/artifacts/brief/artifact.yaml"
        File.write(broken_source, "- 1\n- 2\n")
        result = described_class.validate(root: root, id_or_path: 'brief')
        expect(result).to be_err
        expect(result.code).to eq(:artifact_type_validation_failed)
      end
    end
  end
end
