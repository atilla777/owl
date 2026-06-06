# frozen_string_literal: true

require_relative '../../result'
require_relative '../../validation/internal/section_scanner'
require_relative 'spec_document'

module Owl
  module Specs
    module Internal
      # Parses a structural delta document into operations.
      #
      # A delta is a markdown file holding any of three level-2 sections —
      # `## ADDED Requirements`, `## MODIFIED Requirements`,
      # `## REMOVED Requirements` — each containing `### Requirement:` blocks
      # (full grammar for ADDED/MODIFIED; only the name is read for REMOVED).
      #
      # `parse(body)` returns `Result.ok(added: [block], modified: [block],
      # removed: [name])`, or `Result.err(:invalid_delta)` when:
      #   * a `## <word> Requirements` heading names an unknown operation,
      #   * a requirement name appears in more than one section, or
      #   * the delta carries zero operations.
      module SpecDelta
        SECTION_RE = /\A([A-Za-z]+)\s+Requirements\z/
        OPERATIONS = { 'ADDED' => :added, 'MODIFIED' => :modified, 'REMOVED' => :removed }.freeze

        module_function

        def parse(body)
          sections = collect_sections(body)
          return invalid('no recognized operations were found in the delta') if sections.nil?

          delta = build_delta(body, sections)
          return invalid('the delta contains no ADDED, MODIFIED, or REMOVED operations') if empty?(delta)

          duplicate = cross_section_duplicate(delta)
          return invalid("requirement '#{duplicate}' appears in more than one delta section") if duplicate

          Result.ok(delta)
        end

        # --- internals -----------------------------------------------------

        # Returns the recognized `## ... Requirements` sections as
        # `[{op:, line:, finish:}]`, or `nil` when an unknown operation heading
        # is present (caller maps that to `invalid_delta`).
        def collect_sections(body)
          headings = Owl::Validation::Internal::SectionScanner.headings(body)
          line_count = body.to_s.lines.length
          level2 = headings.each_index.select { |idx| headings[idx][:level] == 2 }
          sections = []
          level2.each_with_index do |idx, position|
            match = headings[idx][:heading].match(SECTION_RE)
            next unless match

            op = OPERATIONS[match[1].upcase]
            return nil unless op

            finish = section_finish(headings, level2, position, line_count)
            sections << { op: op, line: headings[idx][:line], finish: finish }
          end
          sections
        end

        def section_finish(headings, level2, position, line_count)
          next_idx = level2[position + 1]
          next_idx ? headings[next_idx][:line] : line_count
        end

        def build_delta(body, sections)
          lines = body.to_s.lines
          delta = { added: [], modified: [], removed: [] }
          sections.each do |section|
            inner = lines[(section[:line] + 1)...section[:finish]].join
            blocks = SpecDocument.requirement_blocks(inner)
            if section[:op] == :removed
              delta[:removed].concat(blocks.map { |block| block[:name] })
            else
              delta[section[:op]].concat(blocks)
            end
          end
          delta
        end

        def empty?(delta)
          delta[:added].empty? && delta[:modified].empty? && delta[:removed].empty?
        end

        def cross_section_duplicate(delta)
          counts = Hash.new(0)
          names(delta).each { |name| counts[name] += 1 }
          counts.find { |_name, count| count > 1 }&.first
        end

        def names(delta)
          delta[:added].map { |block| block[:name] } +
            delta[:modified].map { |block| block[:name] } +
            delta[:removed]
        end

        def invalid(reason)
          Result.err(
            code: :invalid_delta,
            message: "Invalid delta: #{reason}.",
            details: { reason: reason }
          )
        end

        private_class_method :collect_sections, :section_finish, :build_delta, :empty?,
                             :cross_section_duplicate, :names, :invalid
      end
    end
  end
end
