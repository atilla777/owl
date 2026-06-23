# frozen_string_literal: true

# Guards the documentation acceptance criterion for TASK-0014: the merge_docs
# step context (source + every materialized variant) must describe what the
# `merge_docs` / `owl publish` step actually does — publish artifacts, flip the
# design to `shipped`, and maintain the generated `docs/README.md` index —
# without overselling "merge"/"knowledge base" semantics it does not implement.
RSpec.describe 'merge_docs.context.md honest prose' do
  def repo_root
    File.expand_path('../../..', __dir__)
  end

  def forbidden_patterns
    [/merge published docs/i, /knowledge base/i, /база знаний/i]
  end

  context_files = [
    'workflows/feature/merge_docs.context.md',
    '.owl/workflows/feature/merge_docs.context.md',
    '.owl/workflows/hotfix/merge_docs.context.md',
    '.owl/workflows/refactor/merge_docs.context.md'
  ]

  context_files.each do |rel|
    describe rel do
      let(:body) { File.read(File.join(repo_root, rel)) }

      it 'exists' do
        expect(File.exist?(File.join(repo_root, rel))).to be(true)
      end

      it 'does not oversell with merge/knowledge-base language' do
        forbidden_patterns.each { |pattern| expect(body).not_to match(pattern) }
      end

      it 'describes the design approved→shipped flip' do
        expect(body).to match(/shipped/)
        expect(body).to match(/approved/)
      end

      it 'describes the generated docs/README.md index' do
        expect(body).to include('docs/README.md')
        expect(body).to match(/index/i)
      end

      it 'describes publishing artifacts per publishes rules' do
        expect(body).to match(/publish/i)
        expect(body).to include('publishes')
      end
    end
  end
end
