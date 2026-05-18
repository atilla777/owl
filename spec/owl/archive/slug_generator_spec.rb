# frozen_string_literal: true

require 'owl/tasks/internal/archive/slug_generator'

RSpec.describe Owl::Tasks::Internal::Archive::SlugGenerator do
  describe '.from' do
    it 'lowercases and dasherizes a simple title' do
      expect(described_class.from('Hello World')).to eq('hello-world')
    end

    it 'collapses non-alphanumeric runs into a single dash' do
      expect(described_class.from('Stage 9 — Archive')).to eq('stage-9-archive')
    end

    it 'collapses repeated whitespace and trims edges' do
      expect(described_class.from('  multiple   spaces  ')).to eq('multiple-spaces')
    end

    it 'falls back to "task" when title is only punctuation' do
      expect(described_class.from('!!!')).to eq('task')
    end

    it 'falls back to "task" for an empty title' do
      expect(described_class.from('')).to eq('task')
    end

    it 'falls back to "task" for a nil title' do
      expect(described_class.from(nil)).to eq('task')
    end

    it 'falls back to "task" for a cyrillic-only title (no transliteration in MVP)' do
      expect(described_class.from('Привет мир')).to eq('task')
    end

    it 'truncates very long titles to 60 chars or fewer' do
      title = 'word ' * 80
      slug = described_class.from(title)
      expect(slug.length).to be <= 60
      expect(slug).not_to end_with('-')
      expect(slug).not_to start_with('-')
    end

    it 'is deterministic — same input yields same output' do
      title = 'Some Title 42 — fix!'
      first_call = described_class.from(title)
      second_call = described_class.from(title)
      expect(first_call).to eq(second_call)
    end
  end
end
