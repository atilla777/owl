# frozen_string_literal: true

module Owl
  module Cli
    module Internal
      # The top-level `owl --help` usage text. Extracted from
      # `Owl::Cli::Api` to keep that dispatch module focused.
      module HelpText
        CONTENT = <<~HELP
          Usage: owl <command> [options]

          Commands:
            init                    Initialize a new Owl project layout in the target directory.
            workflow list           List declared workflows (JSON output).
            workflow new            Scaffold a new workflow definition at .owl/workflows/<id>/workflow.yaml.
            workflow validate       Validate a workflow definition by ID or path (JSON output).
            workflow show           Render workflow as ASCII diagram (live by TASK-ID, abstract by --workflow KEY) or return legacy JSON definition by bare KEY.
            workflow source         Show the raw workflow.yaml body for round-trip editing: source show ID.
            workflow context        Show/set a step's context-file body: context <show|set> ID STEP [--variant V] [--body -]. `set` refuses managed workflows.
            workflow register       Add a workflow to .owl/workflows.yaml (project-owned by default; --managed to mark read-only).
            workflow unregister     Remove a workflow from .owl/workflows.yaml (source files untouched).
            artifact-type list      List declared artifact types (JSON output).
            artifact-type new       Scaffold a new artifact type at .owl/artifacts/<id>/artifact.yaml (--from TYPE_ID to clone, --register to add to registry).
            artifact-type validate  Validate an artifact type definition by ID or path (JSON output).
            artifact-type show      Show an artifact type definition by ID (JSON output).
            artifact-type template  Show/set/validate a template body: template <show|set|validate> ID [--template NAME] [--body -]. `set` refuses managed (Owl-shipped) types.
            artifact-type register  Add an artifact type to .owl/artifacts.yaml (project-owned by default; --managed to mark read-only).
            artifact-type unregister Remove an artifact type from .owl/artifacts.yaml (source files untouched).
            config get              Get a value at a settings.* dot-path (JSON output).
            config set              Set a value at a settings.* dot-path; validates before write.
            config show             Print settings + storage roles snapshot (JSON output).
            config validate         Validate .owl/config.yaml (JSON output).
            task create             Create a new task from a registered workflow.
            task list               List tasks from tasks/index.yaml.
            task abandon            Mark a task as abandoned (soft, reversible by editing task.yaml).
            task delete             Physically remove a task directory (requires --force).
            task inspect            Show full task.yaml payload for a TASK-ID.
            task use                Set the current task pointer (.owl/local/current.yaml).
            task current            Show the current task payload.
            task ready-steps        Compute ready steps for a TASK-ID (workflow graph).
            task index rebuild      Rebuild tasks/index.yaml from task.yaml files.
            task tree               Print the full parent → child task tree (JSON).
            task children           List child tasks of a composite parent (JSON).
            task parent             Show parent task (or null) for a TASK-ID.
            task aggregate-status   Aggregate state for a composite task (JSON).
            task child create       Create a child task under a composite parent.
            task claim              Atomically claim a task lease ([TASK-ID] or --next); --ttl, --label, --steal.
            task release            Release a held claim lease: release TASK-ID --token T.
            task heartbeat          Extend a held lease before it expires: heartbeat TASK-ID --token T [--ttl N].
            task claims             List active claim leases across the repo (JSON).
            task available          List runnable, unclaimed tasks ranked best-first (JSON).
            task set-priority       Set a task's integer priority: set-priority TASK-ID N.
            task adopt              Steal a task's claim and reset its running steps to pending: adopt TASK-ID [--token T].
            plan approve            Approve a task's plan, opening the plan_approved gate: approve TASK-ID [--token T].
            plan status             Show plan-approval status for a TASK-ID (approved, plan_sha, gate_open).
            step start              Mark a ready step as running.
            step complete           Mark a running step as done.
            step reopen             Move a completed step back to pending; --cascade also pendifies downstream steps.
            step reset              Move a running step back to pending (claim takeover/abandon recovery).
            step skip               Mark a step as skipped (--reason required).
            step invocation         Print full StepInvocation for a ready step (JSON).
            step report             Write or read a subagent step report (env-agnostic, RFC #1 §5).
            step show               Show merged step + context + artifact_template + task bundle (JSON).
            git lock                Acquire the repo-scoped push lock (serializes commit_push); returns a token. --name, --ttl, --steal.
            git unlock              Release the repo-scoped push lock: git unlock --token T [--name N].
            artifact resolve        Resolve task-scoped artifact path + template + validation rules.
            artifact validate       Validate a task artifact (existence, sections, patterns, front matter).
            verify                  Run the objective verification command (settings.verification.command) for a task and author verification.md; gate_active:false + warning when unconfigured (JSON).
            publish                 Publish task artifacts to the docs storage role per workflow `publishes` rules.
            archive                 Move a completed task into the archive role; or read-only list|show|read of archived tasks.
            recall                  Find similar archived tasks by lexical match (read-only): recall <query> [--limit N] [--root PATH] [--json|--no-json].
            spec                    Project-level domain specs: list|show|path|validate|trace DOMAIN [--strict]; diff|apply DOMAIN --delta PATH [--dry-run] (structural delta-merge); merge TASK-ID [--dry-run] (apply a task's spec_delta + trace gate).
            overlay                 Inspect context overlays for a step: overlay <list|show|validate> STEP-ID [--variant V].
            instructions            Show the next ready step packaged with its SKILL.md summary (JSON).
            next                    Read-only next-action advisor: resolves the task + classifies action.kind (dispatch_step|handoff_composite|stop_blocked|done|no_available_task) (JSON).
            status                  Show workflow progress for a task (steps, progress, blockers, children).
            upgrade                 Refresh this project's copied Owl seed files (skills, managed workflow/artifact files, registry merge) after a gem update; preserves project-owned content. --dry-run to preview.
            self-update             Update the owl-cli gem itself from github main (clone→build→install). --check to compare versions only.

          Global options:
            --help, -h              Show this help message.
            --version, -V           Show owl version.
        HELP
      end
    end
  end
end
