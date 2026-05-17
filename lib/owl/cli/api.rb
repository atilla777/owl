# frozen_string_literal: true

require_relative '../version'
require_relative 'internal/commands/artifact_resolve'
require_relative 'internal/commands/artifact_validate'
require_relative 'internal/commands/config_validate'
require_relative 'internal/commands/init'
require_relative 'internal/commands/step_complete'
require_relative 'internal/commands/step_invocation'
require_relative 'internal/commands/step_skip'
require_relative 'internal/commands/step_start'
require_relative 'internal/commands/task_create'
require_relative 'internal/commands/task_current'
require_relative 'internal/commands/task_index_rebuild'
require_relative 'internal/commands/task_inspect'
require_relative 'internal/commands/task_list'
require_relative 'internal/commands/task_ready_steps'
require_relative 'internal/commands/task_use'
require_relative 'internal/commands/workflow_list'
require_relative 'internal/json_printer'

module Owl
  module Cli
    module Api
      HELP_TEXT = <<~HELP
        Usage: owl <command> [options]

        Commands:
          init                    Initialize a new Owl project layout in the target directory.
          workflow list           List declared workflows (JSON output).
          config validate         Validate .owl/config.yaml (JSON output).
          task create             Create a new task from a registered workflow.
          task list               List tasks from tasks/index.yaml.
          task inspect            Show full task.yaml payload for a TASK-ID.
          task use                Set the current task pointer (.owl/local/current.yaml).
          task current            Show the current task payload.
          task ready-steps        Compute ready steps for a TASK-ID (workflow graph).
          task index rebuild      Rebuild tasks/index.yaml from task.yaml files.
          step start              Mark a ready step as running.
          step complete           Mark a running step as done.
          step skip               Mark a step as skipped (--reason required).
          step invocation         Print full StepInvocation for a ready step (JSON).
          artifact resolve        Resolve task-scoped artifact path + template + validation rules.
          artifact validate       Validate a task artifact (existence, sections, patterns, front matter).

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
        case command
        when 'init'
          Internal::Commands::Init.run(argv: args, stdout: stdout, stderr: stderr, cwd: cwd, env: env)
        when 'workflow'
          dispatch_workflow(args, stdout: stdout, stderr: stderr, cwd: cwd, env: env)
        when 'config'
          dispatch_config(args, stdout: stdout, stderr: stderr, cwd: cwd, env: env)
        when 'task'
          dispatch_task(args, stdout: stdout, stderr: stderr, cwd: cwd, env: env)
        when 'step'
          dispatch_step(args, stdout: stdout, stderr: stderr, cwd: cwd, env: env)
        when 'artifact'
          dispatch_artifact(args, stdout: stdout, stderr: stderr, cwd: cwd, env: env)
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
        case subcommand
        when 'list'
          Internal::Commands::WorkflowList.run(argv: args, stdout: stdout, stderr: stderr, cwd: cwd, env: env)
        else
          unknown_command(stderr, "workflow #{subcommand}".strip)
        end
      end

      def dispatch_config(args, stdout:, stderr:, cwd:, env:)
        subcommand = args.shift
        case subcommand
        when 'validate'
          Internal::Commands::ConfigValidate.run(argv: args, stdout: stdout, stderr: stderr, cwd: cwd, env: env)
        else
          unknown_command(stderr, "config #{subcommand}".strip)
        end
      end

      def dispatch_task(args, stdout:, stderr:, cwd:, env:)
        subcommand = args.shift
        kwargs = { argv: args, stdout: stdout, stderr: stderr, cwd: cwd, env: env }
        case subcommand
        when 'create'       then Internal::Commands::TaskCreate.run(**kwargs)
        when 'list'         then Internal::Commands::TaskList.run(**kwargs)
        when 'inspect'      then Internal::Commands::TaskInspect.run(**kwargs)
        when 'use'          then Internal::Commands::TaskUse.run(**kwargs)
        when 'current'      then Internal::Commands::TaskCurrent.run(**kwargs)
        when 'ready-steps'  then Internal::Commands::TaskReadySteps.run(**kwargs)
        when 'index'        then dispatch_task_index(args, stdout: stdout, stderr: stderr, cwd: cwd, env: env)
        else
          unknown_command(stderr, "task #{subcommand}".strip)
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
