# frozen_string_literal: true

module Owl
  module Specs
    module Internal
      # Dependency-free, deterministic line diff for human preview.
      #
      # `unified(before, after)` returns a single string where each source line
      # is prefixed with ` ` (context), `-` (removed), or `+` (added), computed
      # from a longest-common-subsequence alignment. No external `diff` binary is
      # involved, so the output is stable across platforms.
      module TextDiff
        module_function

        def unified(before, after)
          old = before.to_s.lines
          new = after.to_s.lines
          render(old, new, lcs_table(old, new))
        end

        # --- internals -----------------------------------------------------

        def lcs_table(old, new)
          table = Array.new(old.length + 1) { Array.new(new.length + 1, 0) }
          old.length.downto(1) do |i|
            new.length.downto(1) do |j|
              table[i - 1][j - 1] = if old[i - 1] == new[j - 1]
                                      table[i][j] + 1
                                    else
                                      [table[i - 1][j], table[i][j - 1]].max
                                    end
            end
          end
          table
        end

        def render(old, new, table)
          out = +''
          old_pos = 0
          new_pos = 0
          while old_pos < old.length && new_pos < new.length
            if old[old_pos] == new[new_pos]
              out << line(' ', old[old_pos])
              old_pos += 1
              new_pos += 1
            elsif table[old_pos + 1][new_pos] >= table[old_pos][new_pos + 1]
              out << line('-', old[old_pos])
              old_pos += 1
            else
              out << line('+', new[new_pos])
              new_pos += 1
            end
          end
          out << old[old_pos..].map { |text| line('-', text) }.join
          out << new[new_pos..].map { |text| line('+', text) }.join
        end

        def line(prefix, text)
          text.end_with?("\n") ? "#{prefix}#{text}" : "#{prefix}#{text}\n"
        end

        private_class_method :lcs_table, :render, :line
      end
    end
  end
end
