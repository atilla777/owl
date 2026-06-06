# frozen_string_literal: true

require_relative '../../validation/internal/section_scanner'

module Owl
  module Specs
    module Internal
      # Structural model of a spec body for the delta-merge engine.
      #
      # `parse(body)` splits a spec body into:
      #
      #   { frontmatter:, preamble:, requirements: [{name, heading, body}], tail: }
      #
      # where each requirement spans from its `### Requirement:` line to the next
      # heading of level <= 3 (`#`, `##`, `### `) or EOF — so a nested
      # `#### Scenario:` (level 4) never ends a block, and a trailing `## `
      # section becomes the `tail`. `frontmatter` keeps the raw `---`-fenced text
      # verbatim, `preamble` is everything from the end of the frontmatter up to
      # the first requirement, and `tail` is everything after the last contiguous
      # requirement block. The three slices are byte-contiguous, so
      # `serialize(parse(body)) == body` for any well-formed spec (round-trip
      # identity).
      #
      # Heading detection is delegated to
      # `Owl::Validation::Internal::SectionScanner` (fence-aware) rather than a
      # bespoke regex, so fenced code samples never masquerade as headings.
      module SpecDocument
        REQUIREMENT_RE = /\ARequirement:/
        BOUNDARY_LEVEL = 3

        module_function

        # Parse a spec body into a structural model. Pure; never fails.
        def parse(body)
          source = body.to_s
          frontmatter, rest = split_frontmatter(source)
          blocks = scan_blocks(rest)
          return { frontmatter: frontmatter, preamble: rest, requirements: [], tail: '' } if blocks.empty?

          lines = rest.lines
          preamble = lines[0...blocks.first[:start]].join
          tail = lines[blocks.last[:finish]...lines.length].join
          requirements = blocks.map { |block| block[:requirement] }
          { frontmatter: frontmatter, preamble: preamble, requirements: requirements, tail: tail }
        end

        # Reconstruct the body byte-stably from a model.
        def serialize(model)
          bodies = model[:requirements].map { |req| req[:body] }.join
          "#{model[:frontmatter]}#{model[:preamble]}#{bodies}#{model[:tail]}"
        end

        # Extract every `### Requirement:` block from an arbitrary markdown chunk
        # (used by the delta parser per `## ... Requirements` section). Each block
        # spans to the next heading of level <= 3 or EOF.
        def requirement_blocks(text)
          lines = text.to_s.lines
          headings = Owl::Validation::Internal::SectionScanner.headings(text)
          headings.each_index.filter_map do |idx|
            heading = headings[idx]
            next unless requirement_heading?(heading)

            finish = next_boundary_line(headings, idx, lines.length)
            block_body(lines, heading, finish)
          end
        end

        # --- internals -----------------------------------------------------

        def scan_blocks(rest)
          lines = rest.lines
          headings = Owl::Validation::Internal::SectionScanner.headings(rest)
          first = headings.each_index.find { |idx| requirement_heading?(headings[idx]) }
          return [] unless first

          collect_blocks(headings, lines, first)
        end

        def collect_blocks(headings, lines, index)
          blocks = []
          while index && requirement_heading?(headings[index])
            heading = headings[index]
            next_idx = next_boundary_index(headings, index)
            finish = next_idx ? headings[next_idx][:line] : lines.length
            blocks << { start: heading[:line], finish: finish, requirement: block_body(lines, heading, finish) }
            break if next_idx.nil? || !requirement_heading?(headings[next_idx])

            index = next_idx
          end
          blocks
        end

        def block_body(lines, heading, finish)
          name = heading[:heading].sub(REQUIREMENT_RE, '').strip
          { name: name, heading: heading[:heading], body: lines[heading[:line]...finish].join }
        end

        def next_boundary_index(headings, index)
          ((index + 1)...headings.length).find { |j| headings[j][:level] <= BOUNDARY_LEVEL }
        end

        def next_boundary_line(headings, index, eof)
          next_idx = next_boundary_index(headings, index)
          next_idx ? headings[next_idx][:line] : eof
        end

        def requirement_heading?(heading)
          heading[:level] == 3 && heading[:heading].match?(REQUIREMENT_RE)
        end

        def split_frontmatter(body)
          return ['', body] unless body.start_with?("---\n")

          rest = body[4..]
          index = rest.index("\n---\n")
          return ['', body] unless index

          boundary = 4 + index + 5
          [body[0...boundary], body[boundary..] || '']
        end

        private_class_method :scan_blocks, :collect_blocks, :block_body, :next_boundary_index,
                             :next_boundary_line, :requirement_heading?, :split_frontmatter
      end
    end
  end
end
