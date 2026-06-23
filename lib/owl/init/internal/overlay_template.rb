# frozen_string_literal: true

module Owl
  module Init
    module Internal
      module OverlayTemplate
        module_function

        def for_step(step_id:)
          return brief_overlay if step_id.to_s == 'brief'
          return orchestrator_overlay if step_id.to_s == 'orchestrator'

          generic_overlay(step_id)
        end

        def generic_overlay(step_id)
          <<~MARKDOWN
            <!--
            Optional project overlay for the `#{step_id}` step.

            Content of this file is merged into the step's working context
            alongside the built-in workflow context and the current task
            artifacts. Use it to encode project-specific conventions
            (commit format, design rules, review checklist, etc.) without
            editing Owl-shipped templates.

            Delete this file or leave it empty to opt out — Owl skips
            empty overlays.
            -->
          MARKDOWN
        end

        # The `orchestrator` overlay is a SESSION-level overlay, not a step
        # overlay: `owl-orchestrator` reads it via `owl overlay show orchestrator`
        # before emitting its end-of-run completion report and folds the body in
        # (see `_owl_conventions.md` §8). Shipped as a commented-out stub so the
        # default report structure applies until a project fills it in — Owl
        # skips empty/comment-only overlays.
        def orchestrator_overlay
          <<~MARKDOWN
            <!--
            Optional project overlay for the orchestrator's end-of-run
            completion report (NOT a workflow step).

            Fill this in to make `owl-orchestrator` shape its final, user-facing
            summary to this project's conventions — extra required sections,
            audience emphasis, or mandatory phrasing. The body is folded into
            the report alongside the skill's default structure (what changed for
            the user / technically / verification / docs / commit / next), and
            is written in `settings.language.communication`.

            Example requirements a project might encode here:
            - State the player/end-user-facing change explicitly; if a task is
              technical-only, say so in one sentence and describe the developer
              effect instead.
            - List the exact docs/files synced.

            Delete this file or leave it commented to opt out — Owl skips
            empty overlays and the orchestrator falls back to its default
            report structure.
            -->
          MARKDOWN
        end

        # The `brief` overlay ships with an active completeness checklist (not a
        # commented-out stub): before approving a brief, the agent must walk it
        # and either cover each item or record why it does not apply. Tailor the
        # items to this project's concerns; delete the file to opt out.
        def brief_overlay
          <<~MARKDOWN
            # Brief completeness checklist (project overlay)

            Before setting the brief's front matter to `status: approved`, walk
            this checklist. For each item, either fold the answer into the brief
            (Scenarios / Edge cases / Acceptance criteria) or state explicitly
            that it does not apply. If an item materially affects scope or
            correctness and the request leaves it ambiguous, treat it as a real
            blocker and ask the user rather than guessing.

            - **Security & data access** — new inputs, auth/permission boundaries,
              secrets, filesystem or network reach.
            - **Backward compatibility** — public APIs, on-disk formats, config
              keys, or shipped templates that must not break.
            - **Non-functional requirements** — performance, concurrency, limits,
              idempotency, observability.
            - **Error handling** — failure modes, exit codes / error shapes, retry
              and partial-failure behaviour.
            - **Testing** — what proves each acceptance criterion (unit, integration,
              manual), and the coverage bar the change must meet.

            Replace or extend these items with the conventions that matter for
            this project.
          MARKDOWN
        end
      end
    end
  end
end
