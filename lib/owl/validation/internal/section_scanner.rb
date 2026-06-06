# frozen_string_literal: true

module Owl
  module Validation
    module Internal
      # Shared Markdown structure helper for the semantic checkers.
      #
      # All methods are fence-aware: lines inside fenced code blocks (``` or
      # ~~~) are never treated as headings, and `code_line_mask` exposes the
      # per-line fence state so the placeholder checker can exempt code samples.
      module SectionScanner
        HEADING_RE = /\A\s{0,3}(\#+)\s+(.+?)\s*\z/
        FENCE_RE = /\A\s{0,3}(`{3,}|~{3,})/

        module_function

        # Returns one boolean per line of `body`; true when the line is part of
        # a fenced code block (including the opening/closing fence lines).
        def code_line_mask(body)
          open = false
          fence_char = nil
          body.to_s.lines.map do |line|
            match = line.match(FENCE_RE)
            next open unless match

            if open
              open = false if match[1][0] == fence_char
            else
              open = true
              fence_char = match[1][0]
            end
            true
          end
        end

        # Returns an ordered list of `{heading:, level:, line:}` for every
        # heading in `body` that is not inside a fenced code block.
        def headings(body)
          mask = code_line_mask(body)
          result = []
          body.to_s.lines.each_with_index do |line, index|
            next if mask[index]

            match = line.match(HEADING_RE)
            result << { heading: match[2], level: match[1].length, line: index } if match
          end
          result
        end

        # Returns `{heading:, level:, body:}` segments where each segment's body
        # is the text from its heading line to the next heading of *any* level
        # (or EOF). Used for emptiness detection.
        def sections(body)
          lines = body.to_s.lines
          found = headings(body)
          found.each_with_index.map do |heading, idx|
            start = heading[:line] + 1
            finish = idx + 1 < found.length ? found[idx + 1][:line] : lines.length
            { heading: heading[:heading], level: heading[:level], body: lines[start...finish].join }
          end
        end
      end
    end
  end
end
