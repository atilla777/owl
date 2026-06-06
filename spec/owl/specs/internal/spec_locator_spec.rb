# frozen_string_literal: true

require 'pathname'
require 'stringio'

require 'owl/cli/api'
require 'owl/specs/internal/spec_locator'

RSpec.describe Owl::Specs::Internal::SpecLocator do
  def init_project(root)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: ['init', '--root', root.to_s], stdout: stdout, stderr: stderr, env: {}, cwd: root.to_s)
  end

  describe '.validate_domain' do
    it 'accepts a safe slug' do
      result = described_class.validate_domain('billing-2_x')
      expect(result).to be_ok
      expect(result.value).to eq('billing-2_x')
    end

    it 'rejects path-traversal and uppercase/slashes' do
      ['..', '../x', 'a/b', 'UI', '-leading', '', 'has space'].each do |bad|
        result = described_class.validate_domain(bad)
        expect(result).to be_err, "expected #{bad.inspect} to be rejected"
        expect(result.code).to eq(:invalid_domain)
      end
    end
  end

  describe '.dir' do
    it 'resolves the specs role base directory' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.dir(root: root)
        expect(result).to be_ok
        expect(result.value.to_s).to eq("#{root}/specs")
      end
    end
  end

  describe '.list' do
    it 'returns [] when the specs directory does not exist yet' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.list(root: root)
        expect(result).to be_ok
        expect(result.value).to eq([])
      end
    end
  end

  describe '.read' do
    it 'reads an existing spec body' do
      with_tmp_project do |root|
        init_project(root)
        write("#{root}/specs/ui/spec.md", "body\n")
        result = described_class.read(root: root, domain: 'ui')
        expect(result).to be_ok
        expect(result.value[:body]).to eq("body\n")
      end
    end

    it 'reports spec_not_found (with available domains) for a missing spec' do
      with_tmp_project do |root|
        init_project(root)
        write("#{root}/specs/ui/spec.md", "body\n")
        result = described_class.read(root: root, domain: 'other')
        expect(result).to be_err
        expect(result.code).to eq(:spec_not_found)
        expect(result.details[:available]).to eq(['ui'])
      end
    end

    it 'rejects an invalid domain before touching the filesystem' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.read(root: root, domain: '../secret')
        expect(result).to be_err
        expect(result.code).to eq(:invalid_domain)
      end
    end
  end
end
