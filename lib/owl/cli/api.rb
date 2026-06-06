# frozen_string_literal: true

require_relative '../version'
require_relative 'internal/commands/archive'
require_relative 'internal/commands/archive_list'
require_relative 'internal/commands/archive_read'
require_relative 'internal/commands/archive_show'
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
require_relative 'internal/commands/spec_apply'
require_relative 'internal/commands/spec_diff'
require_relative 'internal/commands/spec_list'
require_relative 'internal/commands/spec_merge'
require_relative 'internal/commands/spec_path'
require_relative 'internal/commands/spec_show'
require_relative 'internal/commands/spec_trace'
require_relative 'internal/commands/spec_validate'
require_relative 'internal/commands/status'
require_relative 'internal/commands/step_complete'
require_relative 'internal/commands/step_invocation'
require_relative 'internal/commands/step_reopen'
require_relative 'internal/commands/step_report'
require_relative 'internal/commands/step_show'
require_relative 'internal/commands/step_skip'
require_relative 'internal/commands/step_start'
require_relative 'internal/commands/task_abandon'
require_relative 'internal/commands/task_aggregate_status'
require_relative 'internal/commands/task_child_create'
require_relative 'internal/commands/task_children'
require_relative 'internal/commands/task_create'
require_relative 'internal/commands/task_current'
require_relative 'internal/commands/task_delete'
require_relative 'internal/commands/task_index_rebuild'
require_relative 'internal/commands/task_inspect'
require_relative 'internal/commands/task_list'
require_relative 'internal/commands/task_parent'
require_relative 'internal/commands/task_ready_steps'
require_relative 'internal/commands/task_tree'
require_relative 'internal/commands/task_use'
require_relative 'internal/commands/workflow_list'
require_relative 'internal/commands/workflow_new'
require_relative 'internal/commands/workflow_diagram_data'
require_relative 'internal/commands/workflow_diagram_renderer'
require_relative 'internal/commands/workflow_show'
require_relative 'internal/commands/workflow_validate'
require_relative 'internal/help_text'
require_relative 'internal/json_printer'

module Owl
  module Cli
    module Api
      HELP_TEXT = Internal::HelpText::CONTENT

      # Top-level commands that delegate straight to a single command module.
      SIMPLE_COMMANDS = {
        'init' => Internal::Commands::Init,
        'publish' => Internal::Commands::Publish,
        'instructions' => Internal::Commands::Instructions,
        'status' => Internal::Commands::Status
      }.freeze

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
        simple = SIMPLE_COMMANDS[command]
        return simple.run(argv: args, **kwargs) if simple

        case command
        when 'workflow'      then dispatch_workflow(args, **kwargs)
        when 'artifact-type' then dispatch_artifact_type(args, **kwargs)
        when 'config'        then dispatch_config(args, **kwargs)
        when 'task'          then dispatch_task(args, **kwargs)
        when 'step'          then dispatch_step(args, **kwargs)
        when 'artifact'      then dispatch_artifact(args, **kwargs)
        when 'archive'       then dispatch_archive(args, **kwargs)
        when 'spec'          then dispatch_spec(args, **kwargs)
        else
          unknown_command(stderr, command)
        end
      end

      def dispatch_archive(args, **)
        case args.first
        when 'list' then Internal::Commands::ArchiveList.run(argv: args.drop(1), **)
        when 'show' then Internal::Commands::ArchiveShow.run(argv: args.drop(1), **)
        when 'read' then Internal::Commands::ArchiveRead.run(argv: args.drop(1), **)
        else Internal::Commands::Archive.run(argv: args, **)
        end
      end

      def dispatch_spec(args, stdout:, stderr:, cwd:, env:)
        subcommand = args.first
        kwargs = { argv: args.drop(1), stdout: stdout, stderr: stderr, cwd: cwd, env: env }
        case subcommand
        when 'list' then Internal::Commands::SpecList.run(**kwargs)
        when 'show' then Internal::Commands::SpecShow.run(**kwargs)
        when 'path' then Internal::Commands::SpecPath.run(**kwargs)
        when 'validate' then Internal::Commands::SpecValidate.run(**kwargs)
        when 'trace' then Internal::Commands::SpecTrace.run(**kwargs)
        when 'diff' then Internal::Commands::SpecDiff.run(**kwargs)
        when 'apply' then Internal::Commands::SpecApply.run(**kwargs)
        when 'merge' then Internal::Commands::SpecMerge.run(**kwargs)
        else unknown_command(stderr, "spec #{subcommand}".strip)
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
        'abandon' => Internal::Commands::TaskAbandon,
        'delete' => Internal::Commands::TaskDelete
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
        when 'reopen'     then Internal::Commands::StepReopen.run(**kwargs)
        when 'skip'       then Internal::Commands::StepSkip.run(**kwargs)
        when 'invocation' then Internal::Commands::StepInvocation.run(**kwargs)
        when 'show'       then Internal::Commands::StepShow.run(**kwargs)
        when 'report'     then Internal::Commands::StepReport.run(**kwargs)
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
