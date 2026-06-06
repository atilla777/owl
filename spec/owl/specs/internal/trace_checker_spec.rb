# frozen_string_literal: true

require 'owl/specs/internal/spec_document'
require 'owl/specs/internal/trace_checker'

RSpec.describe Owl::Specs::Internal::TraceChecker do
  def model_for(body)
    Owl::Specs::Internal::SpecDocument.parse(body)
  end

  # A root with a couple of real files so path-like refs can resolve.
  def with_root
    with_tmp_project do |root|
      write("#{root}/spec/owl/present_spec.rb", "# present\n")
      yield root
    end
  end

  describe '.trace' do
    it 'reports a fully-traced spec (present path ref) as valid' do
      with_root do |root|
        body = <<~MD
          ## Requirements

          ### Requirement: A
          The system SHALL do A.

          #### Scenario: One
          - WHEN x
          - THEN y
          - TEST: spec/owl/present_spec.rb
        MD
        report = described_class.trace(model_for(body), root: root)
        expect(report[:valid]).to be(true)
        expect(report[:summary]).to eq(
          requirements: 1, scenarios: 1, traced: 1, untraced: 0, dangling: 0, unverified: 0
        )
        scenario = report[:requirements].first[:scenarios].first
        expect(scenario).to eq(name: 'One', test_refs: ['spec/owl/present_spec.rb'], status: :traced)
        expect(report[:untraced]).to be_empty
      end
    end

    it 'flags a scenario without a TEST line as untraced (invalid)' do
      with_root do |root|
        body = <<~MD
          ### Requirement: A
          The system SHALL do A.

          #### Scenario: No test
          - WHEN x
          - THEN y
        MD
        report = described_class.trace(model_for(body), root: root)
        expect(report[:valid]).to be(false)
        expect(report[:untraced]).to eq([{ requirement: 'A', scenario: 'No test' }])
        expect(report[:requirements].first[:scenarios].first[:status]).to eq(:untraced)
      end
    end

    it 'flags a path-like ref missing on disk as dangling (invalid)' do
      with_root do |root|
        body = <<~MD
          ### Requirement: A
          The system SHALL do A.

          #### Scenario: Dead link
          - WHEN x
          - THEN y
          - TEST: spec/owl/missing_spec.rb
        MD
        report = described_class.trace(model_for(body), root: root)
        expect(report[:valid]).to be(false)
        expect(report[:dangling]).to eq(
          [{ requirement: 'A', scenario: 'Dead link', ref: 'spec/owl/missing_spec.rb' }]
        )
        expect(report[:requirements].first[:scenarios].first[:status]).to eq(:dangling)
      end
    end

    it 'classifies a non-path prose ref as unverified yet still valid' do
      with_root do |root|
        body = <<~MD
          ### Requirement: A
          The system SHALL do A.

          #### Scenario: Prose
          - WHEN x
          - THEN y
          - TEST: described manually in the QA checklist
        MD
        report = described_class.trace(model_for(body), root: root)
        expect(report[:valid]).to be(true)
        expect(report[:unverified]).to eq(
          [{ requirement: 'A', scenario: 'Prose', ref: 'described manually in the QA checklist' }]
        )
        expect(report[:requirements].first[:scenarios].first[:status]).to eq(:unverified)
      end
    end

    it 'collects multiple TEST lines and is traced when at least one resolves' do
      with_root do |root|
        body = <<~MD
          ### Requirement: A
          The system SHALL do A.

          #### Scenario: Many
          - WHEN x
          - THEN y
          - TEST: spec/owl/present_spec.rb
          - TEST: an extra prose note
        MD
        report = described_class.trace(model_for(body), root: root)
        scenario = report[:requirements].first[:scenarios].first
        expect(scenario[:test_refs]).to eq(['spec/owl/present_spec.rb', 'an extra prose note'])
        expect(scenario[:status]).to eq(:traced)
        # the prose sibling is still surfaced for audit
        expect(report[:unverified].map { |u| u[:ref] }).to eq(['an extra prose note'])
        expect(report[:valid]).to be(true)
      end
    end

    it 'treats a spec with zero requirements as vacuously valid' do
      with_root do |root|
        report = described_class.trace(model_for("# Spec\n\nNo requirements here.\n"), root: root)
        expect(report[:valid]).to be(true)
        expect(report[:requirements]).to be_empty
        expect(report[:summary]).to eq(
          requirements: 0, scenarios: 0, traced: 0, untraced: 0, dangling: 0, unverified: 0
        )
      end
    end

    it 'tolerates bullet/bold/indent markers on the TEST line' do
      with_root do |root|
        body = <<~MD
          ### Requirement: A
          The system SHALL do A.

          #### Scenario: Tolerant
          - WHEN x
          - THEN y
            * **TEST:** spec/owl/present_spec.rb
        MD
        report = described_class.trace(model_for(body), root: root)
        expect(report[:requirements].first[:scenarios].first[:test_refs])
          .to eq(['spec/owl/present_spec.rb'])
        expect(report[:valid]).to be(true)
      end
    end

    it 'does not miscount a #### Scenario heading inside a code fence' do
      with_root do |root|
        body = <<~MD
          ### Requirement: A
          The system SHALL do A.

          #### Scenario: Real
          - WHEN x
          - THEN y
          - TEST: spec/owl/present_spec.rb

          ```
          #### Scenario: Fenced not real
          - TEST: spec/owl/missing_spec.rb
          ```
        MD
        report = described_class.trace(model_for(body), root: root)
        expect(report[:summary][:scenarios]).to eq(1)
        expect(report[:dangling]).to be_empty
        expect(report[:valid]).to be(true)
      end
    end

    it 'classifies a parent-escaping path-like ref as dangling, never traced' do
      with_root do |root|
        body = <<~MD
          ### Requirement: A
          The system SHALL do A.

          #### Scenario: Escape
          - WHEN x
          - THEN y
          - TEST: ../outside.rb
        MD
        report = described_class.trace(model_for(body), root: root)
        expect(report[:valid]).to be(false)
        expect(report[:dangling]).to eq(
          [{ requirement: 'A', scenario: 'Escape', ref: '../outside.rb' }]
        )
        expect(report[:requirements].first[:scenarios].first[:status]).to eq(:dangling)
      end
    end

    it 'keeps an in-root existing ref traced even alongside the traversal guard' do
      with_root do |root|
        body = <<~MD
          ### Requirement: A
          The system SHALL do A.

          #### Scenario: Inside
          - WHEN x
          - THEN y
          - TEST: spec/owl/present_spec.rb
        MD
        report = described_class.trace(model_for(body), root: root)
        expect(report[:valid]).to be(true)
        expect(report[:requirements].first[:scenarios].first[:status]).to eq(:traced)
      end
    end

    it 'resolves an in-root ref that normalizes back inside the root normally' do
      with_root do |root|
        body = <<~MD
          ### Requirement: A
          The system SHALL do A.

          #### Scenario: Normalized
          - WHEN x
          - THEN y
          - TEST: spec/owl/a/../present_spec.rb
        MD
        report = described_class.trace(model_for(body), root: root)
        expect(report[:valid]).to be(true)
        expect(report[:requirements].first[:scenarios].first[:status]).to eq(:traced)
      end
    end

    it 'leaves a prose ref unverified, unaffected by the traversal guard' do
      with_root do |root|
        body = <<~MD
          ### Requirement: A
          The system SHALL do A.

          #### Scenario: Prose with dots
          - WHEN x
          - THEN y
          - TEST: see the ../manual checklist
        MD
        report = described_class.trace(model_for(body), root: root)
        expect(report[:valid]).to be(true)
        expect(report[:requirements].first[:scenarios].first[:status]).to eq(:unverified)
      end
    end

    it 'emits requirements, scenarios and ref lists in deterministic document order' do
      with_root do |root|
        body = <<~MD
          ### Requirement: First
          The system SHALL do first.

          #### Scenario: Fa
          - WHEN x
          - THEN y
          - TEST: a/one.rb

          #### Scenario: Fb
          - WHEN x
          - THEN y
          - TEST: b/two.rb

          ### Requirement: Second
          The system SHALL do second.

          #### Scenario: Sa
          - WHEN x
          - THEN y
          - TEST: c/three.rb
        MD
        report = described_class.trace(model_for(body), root: root)
        expect(report[:requirements].map { |r| r[:name] }).to eq(%w[First Second])
        expect(report[:requirements].first[:scenarios].map { |s| s[:name] }).to eq(%w[Fa Fb])
        expect(report[:dangling].map { |d| d[:ref] }).to eq(%w[a/one.rb b/two.rb c/three.rb])
      end
    end
  end
end
