# frozen_string_literal: true

require_relative '../version'
require_relative 'internal/commands/archive'
require_relative 'internal/commands/artifact_resolve'
require_relative 'internal/commands/artifact_type_list'
require_relative 'internal/commands/artifact_type_new'
require_relative 'internal/commands/artifact_type_show'
require_relative 'internal/commands/artifact_type_validate'
require_relative 'internal/commands/artifact_validate'
require_relative 'internal/commands/config_get'
require_relative 'internal/commands/config_set'
require_relative 'internal/commands/config_show'
require_relative 'internal/commands/config_validate'
require_relative 'internal/commands/init'
require_relative 'internal/commands/instructions'
require_relative 'internal/commands/publish'
require_relative 'internal/commands/status'
require_relative 'internal/commands/step_complete'
require_relative 'internal/commands/step_invocation'
require_relative 'internal/commands/step_show'
require_relative 'internal/commands/step_skip'
require_relative 'internal/commands/step_start'
require_relative 'internal/commands/task_aggregate_status'
require_relative 'internal/commands/task_child_create'
require_relative 'internal/commands/task_children'
require_relative 'internal/commands/task_create'
require_relative 'internal/commands/task_current'
require_relative 'internal/commands/task_index_rebuild'
require_relative 'internal/commands/task_inspect'
require_relative 'internal/commands/task_list'
require_relative 'internal/commands/task_parent'
require_relative 'internal/commands/task_ready_steps'
require_relative 'internal/commands/task_split'
require_relative 'internal/commands/task_tree'
require_relative 'internal/commands/task_use'
require_relative 'internal/commands/workflow_list'
require_relative 'internal/commands/workflow_new'
require_relative 'internal/commands/workflow_diagram_data'
require_relative 'internal/commands/workflow_diagram_renderer'
require_relative 'internal/commands/workflow_show'
require_relative 'internal/commands/workflow_validate'
require_relative 'internal/json_printer'

module Owl
  module Cli
    module Api
      HELP_TEXT = <<~HELP
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
          task split              Convert a task into a composite_task (kind change).
          step start              Mark a ready step as running.
          step complete           Mark a running step as done.
          step skip               Mark a step as skipped (--reason required).
          step invocation         Print full StepInvocation for a ready step (JSON).
          step show               Show merged step + context + artifact_template + task bundle (JSON).
          artifact resolve        Resolve task-scoped artifact path + template + validation rules.
          artifact validate       Validate a task artifact (existence, sections, patterns, front matter).
          publish                 Publish task artifacts to the docs storage role per workflow `publishes` rules.
          archive                 Move a completed task into the archive storage role.
          instructions            Show the next ready step packaged with its SKILL.md summary (JSON).
          status                  Show workflow progress for a task (steps, progress, blockers, children).

        Global options:
          --help, -h              Show this help message.
          --version, -V           Show owl version.
      HELP

      module_function

      def run(argv:, stdout:, stderr:, env: ENV.to_h, cwd: Dir.pwd)
        args = argv.dup

        if args.empty? || args.first == '--help' || args.first == '-h' || args.first == 'help'
          stderr.puts(HELP_TEXT)
          return 0
        end

        if ['--version', '-V'].include?(args.first)
          stderr.puts("owl #{Owl::VERSION}")
          return 0
        end

        command = args.shift
        dispatch_command(command, args, stdout: stdout, stderr: stderr, cwd: cwd, env: env)
      end

      def dispatch_command(command, args, stdout:, stderr:, cwd:, env:)
        kwargs = { stdout: stdout, stderr: stderr, cwd: cwd, env: env }
        case command
        when 'init'          then Internal::Commands::Init.run(argv: args, **kwargs)
        when 'workflow'      then dispatch_workflow(args, **kwargs)
        when 'artifact-type' then dispatch_artifact_type(args, **kwargs)
        when 'config'        then dispatch_config(args, **kwargs)
        when 'task'          then dispatch_task(args, **kwargs)
        when 'step'          then dispatch_step(args, **kwargs)
        when 'artifact'      then dispatch_artifact(args, **kwargs)
        when 'publish'      then Internal::Commands::Publish.run(argv: args, **kwargs)
        when 'archive'      then Internal::Commands::Archive.run(argv: args, **kwargs)
        when 'instructions' then Internal::Commands::Instructions.run(argv: args, **kwargs)
        when 'status'       then Internal::Commands::Status.run(argv: args, **kwargs)
        else
          unknown_command(stderr, command)
        end
      end

      def dispatch_artifact(args, stdout:, stderr:, cwd:, env:)
        subcommand = args.shift
        kwargs = { argv: args, stdout: stdout, stderr: stderr, cwd: cwd, env: env }
        case subcommand
        when 'resolve' then Internal::Commands::ArtifactResolve.run(**kwargs)
        when 'validate' then Internal::Commands::ArtifactValidate.run(**kwargs)
        else
          unknown_command(stderr, "artifact #{subcommand}".strip)
        end
      end

      def dispatch_workflow(args, stdout:, stderr:, cwd:, env:)
        subcommand = args.shift
        kwargs = { argv: args, stdout: stdout, stderr: stderr, cwd: cwd, env: env }
        case subcommand
        when 'list'     then Internal::Commands::WorkflowList.run(**kwargs)
        when 'new'      then Internal::Commands::WorkflowNew.run(**kwargs)
        when 'validate' then Internal::Commands::WorkflowValidate.run(**kwargs)
        when 'show'     then Internal::Commands::WorkflowShow.run(**kwargs)
        else
          unknown_command(stderr, "workflow #{subcommand}".strip)
        end
      end

      def dispatch_artifact_type(args, stdout:, stderr:, cwd:, env:)
        subcommand = args.shift
        kwargs = { argv: args, stdout: stdout, stderr: stderr, cwd: cwd, env: env }
        case subcommand
        when 'list'     then Internal::Commands::ArtifactTypeList.run(**kwargs)
        when 'new'      then Internal::Commands::ArtifactTypeNew.run(**kwargs)
        when 'validate' then Internal::Commands::ArtifactTypeValidate.run(**kwargs)
        when 'show'     then Internal::Commands::ArtifactTypeShow.run(**kwargs)
        else
          unknown_command(stderr, "artifact-type #{subcommand}".strip)
        end
      end

      def dispatch_config(args, stdout:, stderr:, cwd:, env:)
        subcommand = args.shift
        kwargs = { argv: args, stdout: stdout, stderr: stderr, cwd: cwd, env: env }
        case subcommand
        when 'validate' then Internal::Commands::ConfigValidate.run(**kwargs)
        when 'get'      then Internal::Commands::ConfigGet.run(**kwargs)
        when 'set'      then Internal::Commands::ConfigSet.run(**kwargs)
        when 'show'     then Internal::Commands::ConfigShow.run(**kwargs)
        else
          unknown_command(stderr, "config #{subcommand}".strip)
        end
      end

      TASK_SUBCOMMANDS = {
        'create' => Internal::Commands::TaskCreate,
        'list' => Internal::Commands::TaskList,
        'inspect' => Internal::Commands::TaskInspect,
        'use' => Internal::Commands::TaskUse,
        'current' => Internal::Commands::TaskCurrent,
        'ready-steps' => Internal::Commands::TaskReadySteps,
        'tree' => Internal::Commands::TaskTree,
        'children' => Internal::Commands::TaskChildren,
        'parent' => Internal::Commands::TaskParent,
        'aggregate-status' => Internal::Commands::TaskAggregateStatus,
        'split' => Internal::Commands::TaskSplit
      }.freeze

      def dispatch_task(args, stdout:, stderr:, cwd:, env:)
        subcommand = args.shift
        nested_kwargs = { stdout: stdout, stderr: stderr, cwd: cwd, env: env }
        case subcommand
        when 'child' then dispatch_task_child(args, **nested_kwargs)
        when 'index' then dispatch_task_index(args, **nested_kwargs)
        else
          command_module = TASK_SUBCOMMANDS[subcommand]
          return unknown_command(stderr, "task #{subcommand}".strip) unless command_module

          command_module.run(argv: args, **nested_kwargs)
        end
      end

      def dispatch_task_child(args, stdout:, stderr:, cwd:, env:)
        subcommand = args.shift
        case subcommand
        when 'create'
          Internal::Commands::TaskChildCreate.run(argv: args, stdout: stdout, stderr: stderr, cwd: cwd, env: env)
        else
          unknown_command(stderr, "task child #{subcommand}".strip)
        end
      end

      def dispatch_step(args, stdout:, stderr:, cwd:, env:)
        subcommand = args.shift
        kwargs = { argv: args, stdout: stdout, stderr: stderr, cwd: cwd, env: env }
        case subcommand
        when 'start'      then Internal::Commands::StepStart.run(**kwargs)
        when 'complete'   then Internal::Commands::StepComplete.run(**kwargs)
        when 'skip'       then Internal::Commands::StepSkip.run(**kwargs)
        when 'invocation' then Internal::Commands::StepInvocation.run(**kwargs)
        when 'show'       then Internal::Commands::StepShow.run(**kwargs)
        else
          unknown_command(stderr, "step #{subcommand}".strip)
        end
      end

      def dispatch_task_index(args, stdout:, stderr:, cwd:, env:)
        subcommand = args.shift
        case subcommand
        when 'rebuild'
          Internal::Commands::TaskIndexRebuild.run(argv: args, stdout: stdout, stderr: stderr, cwd: cwd, env: env)
        else
          unknown_command(stderr, "task index #{subcommand}".strip)
        end
      end

      def unknown_command(stderr, command)
        Internal::JsonPrinter.failure(
          stderr,
          code: :unknown_command,
          message: "Unknown command: '#{command}'. Run 'owl --help' for usage.",
          details: { command: command.to_s }
        )
      end
    end
  end
end
