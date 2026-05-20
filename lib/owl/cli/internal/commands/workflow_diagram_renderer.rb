# frozen_string_literal: true

module Owl
  module Cli
    module Internal
      module Commands
        module WorkflowDiagramRenderer
          MARK_DONE = '[✓]'
          MARK_CURRENT = '[▶]'
          MARK_PENDING = '[ ]'
          MARK_SKIPPED = '[~]'
          MARK_BLOCKED = '[!]'

          DONE_STATUSES = %w[done].freeze
          SKIPPED_STATUSES = %w[skipped].freeze
          BLOCKED_STATUSES = %w[blocked failed].freeze

          PROGRESS_WIDTH = 10
          PROGRESS_FILLED = '━'
          PROGRESS_EMPTY = '·'

          STEP_ID_COLUMN = 12

          module_function

          def render(data)
            mode = data[:mode]
            case mode
            when :live then render_live(data)
            when :abstract then render_abstract(data)
            else raise ArgumentError, "Unknown diagram mode: #{mode.inspect}"
            end
          end

          def render_live(data)
            lines = []
            lines << header_live(data)
            lines << ''
            lines.concat(step_lines(data[:steps]))
            lines << ''
            lines << blockers_line(data[:blockers] || [])
            lines.join("\n") + "\n"
          end

          def render_abstract(data)
            lines = []
            lines << header_abstract(data)
            lines << ''
            lines.concat(step_lines(data[:steps]))
            lines.join("\n") + "\n"
          end

          def header_live(data)
            task = data[:task] || {}
            progress = data[:progress] || { done: 0, total: 0, pct: 0.0 }
            id = task[:id] || task['id']
            title = task[:title] || task['title']
            workflow_key = task[:workflow_key] || task['workflow_key']
            bar = progress_bar(progress[:done].to_i, progress[:total].to_i)
            label = "#{progress[:done]}/#{progress[:total]} (#{format_pct(progress[:pct])}%)"
            "#{id} \"#{title}\"   workflow: #{workflow_key}   #{bar} #{label}"
          end

          def header_abstract(data)
            workflow_key = data[:workflow_key]
            steps = data[:steps] || []
            "workflow: #{workflow_key}   (#{steps.size} steps)"
          end

          def step_lines(steps)
            return [] if steps.nil? || steps.empty?

            steps.flat_map { |step| [step_line(step), *variant_lines(step)] }
          end

          def step_line(step)
            marker = step_marker(step)
            id = step[:id].to_s
            padded_id = id.ljust(STEP_ID_COLUMN)
            suffix_parts = []
            suffix_parts << "→ #{step[:creates].first}" if step[:creates]&.any?
            suffix_parts << '(optional)' if step[:optional]
            suffix_parts << '← current' if step[:current]
            suffix_parts << "requires: #{step[:requires].join(', ')}" if step[:requires]&.any? && pending?(step)
            suffix = suffix_parts.empty? ? '' : "    #{suffix_parts.join('    ')}"
            "  #{marker} #{padded_id}#{suffix}"
          end

          def variant_lines(step)
            variants = Array(step[:variants])
            return [] if variants.empty?

            default = step[:default_variant].to_s
            chosen = step[:chosen_variant].to_s
            labels = variants.map do |name|
              marker = +name.to_s
              marker << ' [default]' if name.to_s == default
              marker << ' ←' if !chosen.empty? && name.to_s == chosen
              marker
            end
            ["    variants: #{labels.join('  ·  ')}"]
          end

          def step_marker(step)
            status = step[:status].to_s
            return MARK_BLOCKED if BLOCKED_STATUSES.include?(status)
            return MARK_SKIPPED if SKIPPED_STATUSES.include?(status)
            return MARK_DONE if DONE_STATUSES.include?(status)
            return MARK_CURRENT if step[:current]

            MARK_PENDING
          end

          def pending?(step)
            !DONE_STATUSES.include?(step[:status].to_s) &&
              !SKIPPED_STATUSES.include?(step[:status].to_s) &&
              !BLOCKED_STATUSES.include?(step[:status].to_s) &&
              !step[:current]
          end

          def progress_bar(done, total)
            return PROGRESS_EMPTY * PROGRESS_WIDTH if total <= 0

            filled_count = ((done.to_f / total) * PROGRESS_WIDTH).round
            filled_count = PROGRESS_WIDTH if filled_count > PROGRESS_WIDTH
            filled_count = 0 if filled_count.negative?
            (PROGRESS_FILLED * filled_count) + (PROGRESS_EMPTY * (PROGRESS_WIDTH - filled_count))
          end

          def format_pct(value)
            number = value.to_f
            number == number.to_i ? number.to_i.to_s : format('%.1f', number)
          end

          def blockers_line(blockers)
            return 'Blockers: none' if blockers.empty?

            ids = blockers.filter_map { |b| b[:id] || b['id'] }
            "Blockers: #{ids.join(', ')}"
          end
        end
      end
    end
  end
end
