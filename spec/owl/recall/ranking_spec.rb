# frozen_string_literal: true

require 'owl/recall/internal/tokenizer'
require 'owl/recall/internal/scorer'

RSpec.describe 'recall ranking' do
  describe Owl::Recall::Internal::Tokenizer do
    it 'downcases, splits on non-word chars, and drops stopwords' do
      expect(described_class.tokens('The Quick, BROWN fox!')).to eq(%w[quick brown fox])
    end

    it 'tokenizes Cyrillic text with Unicode case folding' do
      expect(described_class.tokens('Семантическая Валидация Артефактов'))
        .to eq(%w[семантическая валидация артефактов])
    end

    it 'drops Russian stopwords' do
      expect(described_class.tokens('поиск по архиву и задачам')).to eq(%w[поиск архиву задачам])
    end

    it 'returns [] for nil and for empty input' do
      expect(described_class.tokens(nil)).to eq([])
      expect(described_class.tokens('   ')).to eq([])
    end
  end

  describe Owl::Recall::Internal::Scorer do
    def corpus
      [
        { task_id: 'TASK-0002', title: 'Spec validation engine',
          text: 'spec validation engine validation rules validation gate' },
        { task_id: 'TASK-0001', title: 'Archive reader',
          text: 'archive reader read archived tasks' },
        { task_id: 'TASK-0003', title: 'Unrelated',
          text: 'gears widgets sprockets' }
      ]
    end

    it 'scores documents that share query terms above those that do not' do
      matches = described_class.rank(query_tokens: %w[validation spec], corpus: corpus, limit: 10)
      expect(matches.first[:task_id]).to eq('TASK-0002')
      expect(matches.map { |m| m[:task_id] }).not_to include('TASK-0003')
      expect(matches.first[:score]).to be > 0
    end

    it 'is deterministic and breaks score ties by task_id ascending' do
      tie_corpus = [
        { task_id: 'TASK-0009', title: 'Beta', text: 'alpha signal' },
        { task_id: 'TASK-0004', title: 'Alpha', text: 'alpha signal' }
      ]
      matches = described_class.rank(query_tokens: %w[alpha], corpus: tie_corpus, limit: 10)
      expect(matches.map { |m| m[:task_id] }).to eq(%w[TASK-0004 TASK-0009])
      expect(matches.map { |m| m[:score] }.uniq.length).to eq(1)
    end

    it 'ranks Cyrillic queries against Cyrillic corpus text' do
      ru_corpus = [
        { task_id: 'TASK-0007', title: 'Семантическая валидация',
          text: 'семантическая валидация артефактов проверка секций' },
        { task_id: 'TASK-0008', title: 'Архивное чтение',
          text: 'чтение архивных задач и артефактов' }
      ]
      matches = described_class.rank(query_tokens: %w[семантическая валидация], corpus: ru_corpus, limit: 10)
      expect(matches.first[:task_id]).to eq('TASK-0007')
    end

    it 'returns [] for an empty query or an empty corpus' do
      expect(described_class.rank(query_tokens: [], corpus: corpus, limit: 5)).to eq([])
      expect(described_class.rank(query_tokens: %w[x], corpus: [], limit: 5)).to eq([])
    end

    it 'produces a single-line, length-bounded, whitespace-collapsed snippet' do
      long = 'spec ' + ('validation rules ' * 40)
      doc = [{ task_id: 'TASK-0005', title: 'Long', text: "#{long}\nsecond line" }]
      snippet = described_class.rank(query_tokens: %w[spec], corpus: doc, limit: 1).first[:snippet]
      expect(snippet).not_to include("\n")
      expect(snippet.length).to be <= 140
      expect(snippet).to end_with('...')
    end
  end
end
