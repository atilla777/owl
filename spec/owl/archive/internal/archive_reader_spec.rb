# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'stringio'
require 'yaml'

require 'owl/archive/internal/archive_reader'
require 'owl/cli/api'

RSpec.describe Owl::Archive::Internal::ArchiveReader do
  def run_cli(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
  end

  def init_project(root)
    run_cli(['init', '--root', root.to_s], cwd: root)
  end

  def archive_dir(root, name)
    dir = Pathname.new("#{root}/tasks/archive/#{name}")
    FileUtils.mkdir_p(dir.to_s)
    dir
  end

  def write_task_yaml(dir, payload)
    write("#{dir}/task.yaml", YAML.dump(payload))
  end

  it 'skips directories whose names do not match the archive pattern' do
    with_tmp_project do |root|
      init_project(root)
      archive_dir(root, 'not-an-archive')
      archive_dir(root, '2026-06-06-TASK-0001-valid').tap { |d| write_task_yaml(d, 'title' => 'Valid') }

      result = described_class.list(root: root)
      expect(result.value[:archived].map { |e| e[:task_id] }).to eq(['TASK-0001'])
    end
  end

  it 'resolves the newest directory when collision suffixes produce multiple matches' do
    with_tmp_project do |root|
      init_project(root)
      archive_dir(root, '2026-06-06-TASK-0001-slug').tap { |d| write_task_yaml(d, 'title' => 'first') }
      newest = archive_dir(root, '2026-06-06-TASK-0001-slug-2')
      write_task_yaml(newest, 'title' => 'second')

      result = described_class.show(root: root, task_id: 'TASK-0001')
      expect(result.value[:path]).to eq(newest.to_s)
      expect(result.value[:title]).to eq('second')
    end
  end

  it 'derives artifact keys from the task.yaml artifact map when present' do
    with_tmp_project do |root|
      init_project(root)
      dir = archive_dir(root, '2026-06-06-TASK-0001-mapped')
      write_task_yaml(dir, 'title' => 'Mapped', 'artifacts' => { 'brief' => 'brief.md' })
      write("#{dir}/brief.md", 'body')
      # An extra .md file that the map intentionally hides.
      write("#{dir}/stray.md", 'stray')

      result = described_class.show(root: root, task_id: 'TASK-0001')
      expect(result.value[:artifacts].map { |a| a[:key] }).to eq(['brief'])
    end
  end

  it 'falls back to *.md filename stems when the task.yaml artifact map is empty' do
    with_tmp_project do |root|
      init_project(root)
      dir = archive_dir(root, '2026-06-06-TASK-0001-files')
      write_task_yaml(dir, 'title' => 'Files', 'artifacts' => [])
      write("#{dir}/design.md", 'd')
      write("#{dir}/brief.md", 'b')

      result = described_class.show(root: root, task_id: 'TASK-0001')
      expect(result.value[:artifacts].map { |a| a[:key] }).to eq(%w[brief design])
    end
  end

  it 'surfaces a storage read error when a mapped artifact file is missing' do
    with_tmp_project do |root|
      init_project(root)
      dir = archive_dir(root, '2026-06-06-TASK-0001-broken')
      write_task_yaml(dir, 'title' => 'Broken', 'artifacts' => { 'brief' => 'gone.md' })

      result = described_class.read(root: root, task_id: 'TASK-0001', artifact_key: 'brief')
      expect(result).to be_err
      expect(result.code).to eq(:file_not_found)
    end
  end
end
