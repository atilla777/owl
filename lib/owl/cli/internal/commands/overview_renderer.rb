# frozen_string_literal: true

require_relative '../../../step_status'

module Owl
  module Cli
    module Internal
      module Commands
        # ASCII renderer for `owl overview`. Draws a parent → child task tree
        # with `├─`/`└─` connectors, a per-node status marker, inline unmet-dep
        # annotation (`⛔ ждёт TASK-XXXX`) and a `◀ текущая` current-task
        # marker. Reuses the shared marker/progress vocabulary of
        # `Owl::StepStatus` (same glyphs as `owl workflow show`).
        module OverviewRenderer
          EMPTY_MESSAGE = 'нет запланированных задач'
          CURRENT_MARK = '◀ текущая'
          DEP_PREFIX = '⛔ ждёт'
          TITLE_WIDTH = 48

          # Task-status → marker mapping, drawn from the shared step-marker
          # vocabulary so the overview reads consistently with `workflow show`.
          DONE_TASK_STATUSES = %w[done archived].freeze
          ABANDONED_TASK_STATUSES = %w[abandoned].freeze
          BLOCKED_TASK_STATUSES = %w[blocked on_hold].freeze
          ACTIVE_TASK_STATUSES = %w[in_progress].freeze

          module_function

          def render(data, compact: false)
            nodes = Array(data[:tree])
            lines = []
            if nodes.empty?
              lines << EMPTY_MESSAGE
            else
              nodes.each { |node| render_node(node, prefix: '', connector: '', compact: compact, lines: lines) }
            end
            lines.concat(warning_lines(data[:warnings]))
            "#{lines.join("\n")}\n"
          end

          def render_node(node, prefix:, connector:, compact:, lines:)
            lines << (prefix + connector + node_line(node, compact: compact))
            children = Array(node[:children])
            child_prefix = prefix + child_prefix_for(connector)
            children.each_with_index do |child, idx|
              last = idx == children.size - 1
              render_node(child, prefix: child_prefix, connector: last ? '└─ ' : '├─ ',
                                 compact: compact, lines: lines)
            end
          end

          # Continuation prefix for a node's own children: the top-level line has
          # no connector (empty), so its children hang at column 0; a `├─` line
          # continues with a `│`, a `└─` line with blank space.
          def child_prefix_for(connector)
            return '' if connector.empty?

            connector.start_with?('└') ? '   ' : '│  '
          end

          def node_line(node, compact:)
            parts = [marker_for(node[:status]), node[:id].to_s, truncate(node[:title])]
            unless compact
              parts << "workflow: #{node[:workflow_key]}" if node[:workflow_key]
              parts << progress_segment(node[:progress])
            end
            parts.concat(annotations(node))
            parts.join(' ')
          end

          def annotations(node)
            notes = []
            notes << CURRENT_MARK if node[:current]
            unmet = Array(node[:unmet_deps])
            notes << "#{DEP_PREFIX} #{unmet.join(', ')}" if unmet.any?
            notes
          end

          def marker_for(status)
            status = status.to_s
            return Owl::StepStatus::MARK_DONE if DONE_TASK_STATUSES.include?(status)
            return Owl::StepStatus::MARK_SKIPPED if ABANDONED_TASK_STATUSES.include?(status)
            return Owl::StepStatus::MARK_BLOCKED if BLOCKED_TASK_STATUSES.include?(status)
            return Owl::StepStatus::MARK_CURRENT if ACTIVE_TASK_STATUSES.include?(status)

            Owl::StepStatus::MARK_PENDING
          end

          def progress_segment(progress)
            progress ||= {}
            done = progress[:done].to_i
            total = progress[:total].to_i
            "#{progress_bar(done, total)} #{done}/#{total}"
          end

          def progress_bar(done, total)
            width = Owl::StepStatus::PROGRESS_WIDTH
            return Owl::StepStatus::PROGRESS_EMPTY * width if total <= 0

            filled = ((done.to_f / total) * width).round
            filled = width if filled > width
            filled = 0 if filled.negative?
            (Owl::StepStatus::PROGRESS_FILLED * filled) + (Owl::StepStatus::PROGRESS_EMPTY * (width - filled))
          end

          def truncate(title)
            text = title.to_s
            return text if text.length <= TITLE_WIDTH

            "#{text[0, TITLE_WIDTH - 1]}…"
          end

          def warning_lines(warnings)
            Array(warnings).map do |warning|
              code = warning[:code] || warning['code']
              path = warning[:at_path] || warning['at_path']
              "⚠️  #{code} @ #{path}"
            end
          end
        end
      end
    end
  end
end
