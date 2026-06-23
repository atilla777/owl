# frozen_string_literal: true

require 'pathname'

require 'owl/cli/api'
require 'owl/publish/internal/docs_index'

RSpec.describe Owl::Publish::Internal::DocsIndex do
  def init_project(root)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: ['init', '--root', root.to_s], stdout: stdout, stderr: stderr,
                      env: {}, cwd: root.to_s)
  end

  def published_design(status: 'shipped', summary: 'A summary')
    <<~MD
      ---
      status: #{status}
      summary: "#{summary}"
      ---
      # Design
    MD
  end

  describe '.regenerate' do
    it 'lists every docs/TASK-*/ doc with a link, sorted by TASK-ID' do
      with_tmp_project do |root|
        init_project(root)
        write("#{root}/docs/TASK-0002/design.md", published_design(summary: 'Second'))
        write("#{root}/docs/TASK-0001/design.md", published_design(summary: 'First'))

        result = described_class.regenerate(root: root, dry_run: false)
        expect(result).to be_ok
        expect(result.value).to eq(updated: true, path: 'docs/README.md')

        readme = Pathname.new("#{root}/docs/README.md").read
        expect(readme).to include('[TASK-0001/design.md](TASK-0001/design.md) — First')
        expect(readme).to include('[TASK-0002/design.md](TASK-0002/design.md) — Second')
        expect(readme.index('TASK-0001')).to be < readme.index('TASK-0002')
      end
    end

    it 'does not write on dry-run' do
      with_tmp_project do |root|
        init_project(root)
        write("#{root}/docs/TASK-0001/design.md", published_design)

        result = described_class.regenerate(root: root, dry_run: true)
        expect(result).to be_ok
        expect(result.value).to eq(updated: false, path: 'docs/README.md')
        expect(Pathname.new("#{root}/docs/README.md").exist?).to be(false)
      end
    end

    it 'is deterministic: two runs over the same doc set yield identical bytes' do
      with_tmp_project do |root|
        init_project(root)
        write("#{root}/docs/TASK-0001/design.md", published_design(summary: 'Stable'))

        described_class.regenerate(root: root, dry_run: false)
        first = Pathname.new("#{root}/docs/README.md").read
        described_class.regenerate(root: root, dry_run: false)
        second = Pathname.new("#{root}/docs/README.md").read

        expect(second).to eq(first)
      end
    end

    it 'omits the summary suffix when front-matter has none' do
      with_tmp_project do |root|
        init_project(root)
        write("#{root}/docs/TASK-0001/notes.md", "# Notes only\n")

        described_class.regenerate(root: root, dry_run: false)
        readme = Pathname.new("#{root}/docs/README.md").read
        expect(readme).to include('- [TASK-0001/notes.md](TASK-0001/notes.md)')
        expect(readme).not_to match(/notes\.md\) —/)
      end
    end

    it 'does not back up an existing index (regenerates in place)' do
      with_tmp_project do |root|
        init_project(root)
        write("#{root}/docs/TASK-0001/design.md", published_design)

        described_class.regenerate(root: root, dry_run: false)
        described_class.regenerate(root: root, dry_run: false)

        backups = Pathname.new("#{root}/docs").children.select { |c| c.basename.to_s.include?('README.md.bak') }
        expect(backups).to be_empty
      end
    end

    it 'renders a placeholder when there are no published task docs' do
      with_tmp_project do |root|
        init_project(root)

        described_class.regenerate(root: root, dry_run: false)
        readme = Pathname.new("#{root}/docs/README.md").read
        expect(readme).to include('No published docs yet')
      end
    end
  end
end
