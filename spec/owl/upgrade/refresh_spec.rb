# frozen_string_literal: true

require 'owl/upgrade/api'
require 'owl/init/api'
require 'owl/artifacts/api'

RSpec.describe Owl::Upgrade::Api, '.refresh' do
  def init_project(root)
    Owl::Init::Api.scaffold(root: root)
  end

  it 'restores a stale managed file and records a backup' do
    with_tmp_project do |root|
      init_project(root)
      managed = "#{root}/.owl/artifacts/plan/templates/default.md"
      File.write(managed, "STALE\n")

      result = described_class.refresh(root: root)
      expect(result).to be_ok
      expect(result.value[:replaced]).to include('.owl/artifacts/plan/templates/default.md')
      expect(File.read(managed)).to include('## Goal')
      expect(result.value[:backed_up]).to include('.owl/artifacts/plan/templates/default.md')
      expect(File).to exist("#{result.value[:backup_dir]}/.owl/artifacts/plan/templates/default.md")
    end
  end

  it 'preserves project-owned content (overlays + managed:false clone)' do
    with_tmp_project do |root|
      init_project(root)
      Owl::Artifacts::Api.scaffold(root: root, id: 'myplan', from: 'plan')
      Owl::Artifacts::Api.register(root: root, id: 'myplan', managed: false)
      File.write("#{root}/.owl/overlays/plan.md", "MY OVERLAY\n")
      File.write("#{root}/.owl/artifacts/myplan/templates/default.md", "MINE\n")

      described_class.refresh(root: root)

      expect(File.read("#{root}/.owl/overlays/plan.md")).to eq("MY OVERLAY\n")
      expect(File.read("#{root}/.owl/artifacts/myplan/templates/default.md")).to eq("MINE\n")
      # myplan stays registered after the registry merge
      keys = Owl::Artifacts::Api.list(root: root).value.map { |a| a[:key] }
      expect(keys).to include('myplan')
    end
  end

  it 'preserves a seeded id that the project re-registered as managed:false' do
    with_tmp_project do |root|
      init_project(root)
      # shadow the managed `plan` entry as project-owned
      Owl::Artifacts::Api.register(root: root, id: 'plan', managed: false, force: true)
      File.write("#{root}/.owl/artifacts/plan/templates/default.md", "PROJECT OWNED\n")

      result = described_class.refresh(root: root)
      expect(result.value[:preserved]).to include('.owl/artifacts/plan/templates/default.md')
      expect(File.read("#{root}/.owl/artifacts/plan/templates/default.md")).to eq("PROJECT OWNED\n")
    end
  end

  it 'dry-run reports the plan without writing' do
    with_tmp_project do |root|
      init_project(root)
      managed = "#{root}/.owl/artifacts/plan/templates/default.md"
      File.write(managed, "STALE\n")

      result = described_class.refresh(root: root, dry_run: true)
      expect(result.value[:dry_run]).to be(true)
      expect(result.value[:replaced]).to include('.owl/artifacts/plan/templates/default.md')
      expect(File.read(managed)).to eq("STALE\n")
    end
  end

  it 'skips backup when backup: false' do
    with_tmp_project do |root|
      init_project(root)
      File.write("#{root}/.owl/artifacts/plan/templates/default.md", "STALE\n")
      result = described_class.refresh(root: root, backup: false)
      expect(result.value[:backed_up]).to eq([])
      expect(File).not_to exist("#{root}/.owl/.backup")
    end
  end

  it 'stamps owl.version and reports from/to' do
    with_tmp_project do |root|
      init_project(root)
      Owl::Config::Api.write_key(root: root, key: 'owl.version', value: '0.0.1')
      result = described_class.refresh(root: root)
      expect(result.value[:version][:from]).to eq('0.0.1')
      expect(result.value[:version][:to]).to eq(Owl::VERSION)
      expect(Owl::Config::Api.read_key(root: root, key: 'owl.version').value[:value]).to eq(Owl::VERSION)
    end
  end
end
