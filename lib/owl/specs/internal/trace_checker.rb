# frozen_string_literal: true

require 'pathname'

require_relative '../../storage/api'
require_relative '../../validation/internal/section_scanner'

module Owl
  module Specs
    module Internal
      # Computes requirement -> scenario -> test traceability coverage over a
      # parsed `SpecDocument` model (P4). Pure and read-only: it never writes,
      # and the only filesystem access is `Owl::Storage::Api.exists?` to confirm
      # that a path-like `- TEST:` reference resolves under the project root.
      #
      # Inside each `#### Scenario:` block (a sibling of the `- WHEN`/`- THEN`
      # bullets) one or more `- TEST: <reference>` lines name the proving
      # test(s). Matching is tolerant of leading bullet/quote markers, bold, and
      # indentation, exactly like the WHEN/THEN checker.
      #
      # Per scenario:
      #   * no `- TEST:` line                       -> untraced
      #   * a path-like ref (`/` and a `.ext` tail) -> existence-checked:
      #       present -> traced, missing -> dangling
      #   * a non-path ref (a prose description/id)  -> unverified
      #
      # `valid` is true when there is no untraced scenario AND no dangling ref;
      # unverified refs are surfaced for human audit but still count as traced.
      # A spec with zero requirements is vacuously `valid`. All output lists are
      # emitted in document order (deterministic).
      module TraceChecker
        TEST_RE = /^[\s>*-]*\**\s*TEST:\s*(.+?)\s*$/
        SCENARIO_RE = /\AScenario:/
        SCENARIO_LEVEL = 4

        module_function

        def trace(model, root:)
          state = { untraced: [], dangling: [], unverified: [], traced: 0, scenarios: 0 }
          requirements = Array(model[:requirements]).map do |requirement|
            trace_requirement(requirement, root, state)
          end

          {
            requirements: requirements,
            summary: summary(requirements.length, state),
            untraced: state[:untraced],
            dangling: state[:dangling],
            unverified: state[:unverified],
            valid: state[:untraced].empty? && state[:dangling].empty?
          }
        end

        # --- internals -----------------------------------------------------

        def trace_requirement(requirement, root, state)
          name = requirement[:name].to_s
          scenarios = scenario_blocks(requirement[:body].to_s).map do |scenario|
            state[:scenarios] += 1
            classify_scenario(name, scenario, root, state)
          end
          { name: name, scenarios: scenarios }
        end

        def classify_scenario(requirement_name, scenario, root, state)
          name = scenario[:name]
          refs = scenario[:test_refs]
          status = scenario_status(requirement_name, name, refs, root, state)
          state[:traced] += 1 if status == :traced
          { name: name, test_refs: refs, status: status }
        end

        def scenario_status(requirement_name, scenario_name, refs, root, state)
          if refs.empty?
            state[:untraced] << { requirement: requirement_name, scenario: scenario_name }
            return :untraced
          end

          classifications = refs.map do |ref|
            classify_ref(requirement_name, scenario_name, ref, root, state)
          end
          rollup(classifications)
        end

        def classify_ref(requirement_name, scenario_name, ref, root, state)
          unless path_like?(ref)
            state[:unverified] << { requirement: requirement_name, scenario: scenario_name, ref: ref }
            return :unverified
          end

          resolved = resolve_in_root(root, ref)
          if resolved && Owl::Storage::Api.exists?(path: resolved)
            :traced
          else
            state[:dangling] << { requirement: requirement_name, scenario: scenario_name, ref: ref }
            :dangling
          end
        end

        # Lexically normalize the root-joined ref (expanding `.`/`..` WITHOUT
        # touching the filesystem) and require it to stay under the normalized
        # project root, so a path-like ref escaping the repo (e.g. `../x.rb`)
        # can never be counted as traced. Returns the normalized in-root path
        # to existence-check, or `nil` when the ref escapes the root. Pure path
        # math — not filesystem I/O.
        def resolve_in_root(root, ref)
          root_path = Pathname.new(root.to_s).cleanpath
          joined = (root_path + ref).cleanpath
          return joined.to_s if joined == root_path || joined.to_s.start_with?("#{root_path}/")

          nil
        end

        def rollup(classifications)
          return :dangling if classifications.include?(:dangling)
          return :traced if classifications.include?(:traced)

          :unverified
        end

        def path_like?(ref)
          ref.include?('/') && ref.match?(/\.\w+$/)
        end

        # Split a requirement body into its `#### Scenario:` blocks, reusing the
        # fence-aware SectionScanner so a `#### Scenario` inside a code fence is
        # never miscounted. A scenario spans to the next heading of level <= 4
        # (another scenario, the next requirement, or a section) or EOF.
        def scenario_blocks(body)
          lines = body.lines
          mask = Owl::Validation::Internal::SectionScanner.code_line_mask(body)
          headings = Owl::Validation::Internal::SectionScanner.headings(body)
          headings.each_index.filter_map do |idx|
            heading = headings[idx]
            next unless scenario_heading?(heading)

            finish = next_boundary_line(headings, idx, lines.length)
            scenario_block(lines, mask, heading, finish)
          end
        end

        def scenario_block(lines, mask, heading, finish)
          name = heading[:heading].sub(SCENARIO_RE, '').strip
          start = heading[:line] + 1
          { name: name, test_refs: test_refs(lines, mask, start, finish) }
        end

        # Collect `- TEST:` references in body order, skipping lines that fall
        # inside a fenced code block (a `- TEST:` shown as a sample, not a real
        # annotation) and stripping any wrapping bold markers from the value.
        def test_refs(lines, mask, start, finish)
          (start...finish).filter_map do |index|
            next if mask[index]

            match = lines[index].match(TEST_RE)
            match && clean_ref(match[1])
          end
        end

        def clean_ref(value)
          value.strip.sub(/\A\*+\s*/, '').sub(/\s*\*+\z/, '').strip
        end

        def next_boundary_line(headings, index, eof)
          next_idx = ((index + 1)...headings.length).find { |j| headings[j][:level] <= SCENARIO_LEVEL }
          next_idx ? headings[next_idx][:line] : eof
        end

        def scenario_heading?(heading)
          heading[:level] == SCENARIO_LEVEL && heading[:heading].match?(SCENARIO_RE)
        end

        def summary(requirement_count, state)
          {
            requirements: requirement_count,
            scenarios: state[:scenarios],
            traced: state[:traced],
            untraced: state[:untraced].length,
            dangling: state[:dangling].length,
            unverified: state[:unverified].length
          }
        end

        private_class_method :trace_requirement, :classify_scenario, :scenario_status,
                             :classify_ref, :resolve_in_root, :rollup, :path_like?, :scenario_blocks,
                             :scenario_block, :test_refs, :clean_ref, :next_boundary_line,
                             :scenario_heading?, :summary
      end
    end
  end
end
