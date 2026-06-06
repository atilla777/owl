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
            artifact-type list      List declared artifact types (JSON output).
            artifact-type new       Scaffold a new artifact type definition at .owl/artifacts/<id>/artifact.yaml.
            artifact-type validate  Validate an artifact type definition by ID or path (JSON output).
            artifact-type show      Show an artifact type definition by ID (JSON output).
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
            step start              Mark a ready step as running.
            step complete           Mark a running step as done.
            step reopen             Move a completed step back to pending; --cascade also pendifies downstream steps.
            step skip               Mark a step as skipped (--reason required).
            step invocation         Print full StepInvocation for a ready step (JSON).
            step report             Write or read a subagent step report (env-agnostic, RFC #1 §5).
            step show               Show merged step + context + artifact_template + task bundle (JSON).
            artifact resolve        Resolve task-scoped artifact path + template + validation rules.
            artifact validate       Validate a task artifact (existence, sections, patterns, front matter).
            publish                 Publish task artifacts to the docs storage role per workflow `publishes` rules.
            archive                 Move a completed task into the archive role; or read-only list|show|read of archived tasks.
            spec                    Project-level domain specs: list|show DOMAIN|path DOMAIN|validate DOMAIN (read/resolve/validate).
            instructions            Show the next ready step packaged with its SKILL.md summary (JSON).
            status                  Show workflow progress for a task (steps, progress, blockers, children).

          Global options:
            --help, -h              Show this help message.
            --version, -V           Show owl version.
        HELP
      end
    end
  end
end
