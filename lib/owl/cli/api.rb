# frozen_string_literal: true

require_relative '../version'
require_relative 'internal/commands/archive'
require_relative 'internal/commands/archive_list'
require_relative 'internal/commands/archive_read'
require_relative 'internal/commands/archive_show'
require_relative 'internal/commands/artifact_resolve'
require_relative 'internal/commands/artifact_type_list'
require_relative 'internal/commands/artifact_type_new'
require_relative 'internal/commands/artifact_type_register'
require_relative 'internal/commands/artifact_type_show'
require_relative 'internal/commands/artifact_type_template'
require_relative 'internal/commands/artifact_type_validate'
require_relative 'internal/commands/artifact_validate'
require_relative 'internal/commands/config_get'
require_relative 'internal/commands/config_set'
require_relative 'internal/commands/config_show'
require_relative 'internal/commands/config_validate'
require_relative 'internal/commands/commit_push'
require_relative 'internal/commands/doctor'
require_relative 'internal/commands/git_lock'
require_relative 'internal/commands/git_unlock'
require_relative 'internal/commands/init'
require_relative 'internal/commands/instructions'
require_relative 'internal/commands/next'
require_relative 'internal/commands/overlay'
require_relative 'internal/commands/overview'
require_relative 'internal/commands/plan_approve'
require_relative 'internal/commands/plan_status'
require_relative 'internal/commands/publish'
require_relative 'internal/commands/recall'
require_relative 'internal/commands/self_update'
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
require_relative 'internal/commands/step_reset'
require_relative 'internal/commands/step_show'
require_relative 'internal/commands/step_skip'
require_relative 'internal/commands/step_start'
require_relative 'internal/commands/task_abandon'
require_relative 'internal/commands/task_adopt'
require_relative 'internal/commands/task_aggregate_status'
require_relative 'internal/commands/task_available'
require_relative 'internal/commands/task_child_create'
require_relative 'internal/commands/task_children'
require_relative 'internal/commands/task_claim'
require_relative 'internal/commands/task_claims'
require_relative 'internal/commands/task_create'
require_relative 'internal/commands/task_heartbeat'
require_relative 'internal/commands/task_current'
require_relative 'internal/commands/task_delete'
require_relative 'internal/commands/task_dep'
require_relative 'internal/commands/task_index_rebuild'
require_relative 'internal/commands/task_inspect'
require_relative 'internal/commands/task_label'
require_relative 'internal/commands/task_list'
require_relative 'internal/commands/task_parent'
require_relative 'internal/commands/task_query'
require_relative 'internal/commands/task_ready'
require_relative 'internal/commands/task_ready_steps'
require_relative 'internal/commands/task_release'
require_relative 'internal/commands/task_set_priority'
require_relative 'internal/commands/task_set_status'
require_relative 'internal/commands/task_tree'
require_relative 'internal/commands/task_use'
require_relative 'internal/commands/upgrade'
require_relative 'internal/commands/verify'
require_relative 'internal/commands/version'
require_relative 'internal/commands/workflow_context'
require_relative 'internal/commands/workflow_list'
require_relative 'internal/commands/workflow_new'
require_relative 'internal/commands/workflow_register'
require_relative 'internal/commands/workflow_source'
require_relative 'internal/commands/workflow_diagram_data'
require_relative 'internal/commands/workflow_diagram_renderer'
require_relative 'internal/commands/workflow_show'
require_relative 'internal/commands/workflow_validate'
require_relative 'internal/help_text'
require_relative 'internal/json_printer'

module Owl
  module Cli
    module Api # rubocop:disable Metrics/ModuleLength
      HELP_TEXT = Internal::HelpText::CONTENT

      # Top-level commands that delegate straight to a single command module.
      SIMPLE_COMMANDS = {
        'init' => Internal::Commands::Init,
        'publish' => Internal::Commands::Publish,
        'instructions' => Internal::Commands::Instructions,
        'next' => Internal::Commands::Next,
        'overview' => Internal::Commands::Overview,
        'status' => Internal::Commands::Status,
        'upgrade' => Internal::Commands::Upgrade,
        'verify' => Internal::Commands::Verify,
        'version' => Internal::Commands::Version,
        'self-update' => Internal::Commands::SelfUpdate,
        'doctor' => Internal::Commands::Doctor
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

      # Command groups whose subcommands are routed by a `dispatch_<group>`
      # method. Kept as a table so `dispatch_command` stays flat.
      GROUP_DISPATCHERS = {
        'workflow' => :dispatch_workflow,
        'artifact-type' => :dispatch_artifact_type,
        'config' => :dispatch_config,
        'git' => :dispatch_git,
        'task' => :dispatch_task,
        'plan' => :dispatch_plan,
        'step' => :dispatch_step,
        'artifact' => :dispatch_artifact,
        'archive' => :dispatch_archive,
        'commit-push' => :dispatch_commit_push,
        'recall' => :dispatch_recall,
        'spec' => :dispatch_spec
      }.freeze

      def dispatch_command(command, args, stdout:, stderr:, cwd:, env:)
        kwargs = { stdout: stdout, stderr: stderr, cwd: cwd, env: env }
        simple = SIMPLE_COMMANDS[command]
        return simple.run(argv: args, **kwargs) if simple
        return Internal::Commands::Overlay.run(argv: args, **kwargs) if command == 'overlay'

        group = GROUP_DISPATCHERS[command]
        if group
          return group_help(command, args, stdout: stdout, stderr: stderr) if group_help_request?(command, args)

          return send(group, args, **kwargs)
        end

        unknown_command(stderr, command)
      end

      # Help flags that, on their own, ask for a group's subcommand listing.
      HELP_FLAGS = %w[--help -h].freeze

      # A group help is requested when the group routes by subcommand verb
      # (registered in HelpText::GROUP_SUBCOMMANDS) and no real subcommand was
      # supplied — i.e. no args at all, or only help/`--json` flags. A concrete
      # but unknown verb (`owl step bogus`) is NOT a help request and still
      # falls through to the group's `unknown_command`.
      def group_help_request?(command, args)
        return false unless Internal::HelpText::GROUP_SUBCOMMANDS.key?(command)
        return true if args.empty?

        args.all? { |arg| HELP_FLAGS.include?(arg) || arg == '--json' }
      end

      def group_help(command, args, stdout:, stderr:)
        subcommands = Internal::HelpText::GROUP_SUBCOMMANDS.fetch(command)
        if args.include?('--json')
          return Internal::JsonPrinter.success(stdout, { ok: true, command: command, subcommands: subcommands })
        end

        stderr.puts(Internal::HelpText.group_help_text(command, subcommands))
        0
      end

      def dispatch_archive(args, **)
        case args.first
        when 'list' then Internal::Commands::ArchiveList.run(argv: args.drop(1), **)
        when 'show' then Internal::Commands::ArchiveShow.run(argv: args.drop(1), **)
        when 'read' then Internal::Commands::ArchiveRead.run(argv: args.drop(1), **)
        else Internal::Commands::Archive.run(argv: args, **)
        end
      end

      def dispatch_recall(args, **)
        Internal::Commands::Recall.run(argv: args, **)
      end

      def dispatch_commit_push(args, **)
        Internal::Commands::CommitPush.run(argv: args, **)
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
        when 'list'       then Internal::Commands::WorkflowList.run(**kwargs)
        when 'new'        then Internal::Commands::WorkflowNew.run(**kwargs)
        when 'validate'   then Internal::Commands::WorkflowValidate.run(**kwargs)
        when 'show'       then Internal::Commands::WorkflowShow.run(**kwargs)
        when 'source'     then Internal::Commands::WorkflowSource.run(**kwargs)
        when 'context'    then Internal::Commands::WorkflowContext.run(**kwargs)
        when 'register'   then Internal::Commands::WorkflowRegister.run(**kwargs)
        when 'unregister' then Internal::Commands::WorkflowRegister.unregister(**kwargs)
        else
          unknown_command(stderr, "workflow #{subcommand}".strip)
        end
      end

      def dispatch_artifact_type(args, stdout:, stderr:, cwd:, env:)
        subcommand = args.shift
        kwargs = { argv: args, stdout: stdout, stderr: stderr, cwd: cwd, env: env }
        case subcommand
        when 'list'       then Internal::Commands::ArtifactTypeList.run(**kwargs)
        when 'new'        then Internal::Commands::ArtifactTypeNew.run(**kwargs)
        when 'validate'   then Internal::Commands::ArtifactTypeValidate.run(**kwargs)
        when 'show'       then Internal::Commands::ArtifactTypeShow.run(**kwargs)
        when 'template'   then Internal::Commands::ArtifactTypeTemplate.run(**kwargs)
        when 'register'   then Internal::Commands::ArtifactTypeRegister.run(**kwargs)
        when 'unregister' then Internal::Commands::ArtifactTypeRegister.unregister(**kwargs)
        else
          unknown_command(stderr, "artifact-type #{subcommand}".strip)
        end
      end

      def dispatch_git(args, stdout:, stderr:, cwd:, env:)
        subcommand = args.shift
        kwargs = { argv: args, stdout: stdout, stderr: stderr, cwd: cwd, env: env }
        case subcommand
        when 'lock'   then Internal::Commands::GitLock.run(**kwargs)
        when 'unlock' then Internal::Commands::GitUnlock.run(**kwargs)
        else unknown_command(stderr, "git #{subcommand}".strip)
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
        'delete' => Internal::Commands::TaskDelete,
        'claim' => Internal::Commands::TaskClaim,
        'release' => Internal::Commands::TaskRelease,
        'heartbeat' => Internal::Commands::TaskHeartbeat,
        'claims' => Internal::Commands::TaskClaims,
        'available' => Internal::Commands::TaskAvailable,
        'set-priority' => Internal::Commands::TaskSetPriority,
        'set-status' => Internal::Commands::TaskSetStatus,
        'query' => Internal::Commands::TaskQuery,
        'adopt' => Internal::Commands::TaskAdopt,
        'ready' => Internal::Commands::TaskReady
      }.freeze

      def dispatch_task(args, stdout:, stderr:, cwd:, env:)
        subcommand = args.shift
        nested_kwargs = { stdout: stdout, stderr: stderr, cwd: cwd, env: env }
        case subcommand
        when 'child' then dispatch_task_child(args, **nested_kwargs)
        when 'index' then dispatch_task_index(args, **nested_kwargs)
        when 'label' then dispatch_task_label(args, **nested_kwargs)
        when 'dep' then dispatch_task_dep(args, **nested_kwargs)
        else
          command_module = TASK_SUBCOMMANDS[subcommand]
          return unknown_command(stderr, "task #{subcommand}".strip) unless command_module

          command_module.run(argv: args, **nested_kwargs)
        end
      end

      # Subcommand verbs for the nested `task <group>` routers, used to make
      # `owl task <group>` (bare) and `owl task <group> --help` reachable —
      # otherwise both fell through to `unknown_command`, which reads as "this
      # command does not exist" even though `owl task --help` advertises it.
      TASK_SUBGROUP_SUBCOMMANDS = {
        'child' => %w[create],
        'index' => %w[rebuild],
        'label' => %w[add rm],
        'dep' => %w[add rm remove list]
      }.freeze

      # Intercept a nested `task <group>` invocation that carries no real verb:
      # `--help`/`-h` (or a lone `--json`) prints the subcommand listing (exit
      # 0), a bare group returns a structured `missing_subcommand` error (exit
      # 1). Returns an Integer exit code when handled, or nil to fall through to
      # the group's real dispatch.
      def task_subgroup_intercept(group, args, stdout:, stderr:)
        subs = TASK_SUBGROUP_SUBCOMMANDS.fetch(group)
        label = "task #{group}"
        if args.empty?
          return Internal::JsonPrinter.failure(
            stderr,
            code: :missing_subcommand,
            message: "Missing subcommand for '#{label}'. Expected one of: #{subs.join(', ')}.",
            details: { group: label, subcommands: subs }
          )
        end
        return nil unless args.all? { |arg| HELP_FLAGS.include?(arg) || arg == '--json' }

        if args.include?('--json')
          return Internal::JsonPrinter.success(stdout, { ok: true, command: label, subcommands: subs })
        end

        stderr.puts(Internal::HelpText.group_help_text(label, subs))
        0
      end

      def dispatch_task_child(args, stdout:, stderr:, cwd:, env:)
        intercepted = task_subgroup_intercept('child', args, stdout: stdout, stderr: stderr)
        return intercepted if intercepted

        subcommand = args.shift
        case subcommand
        when 'create'
          Internal::Commands::TaskChildCreate.run(argv: args, stdout: stdout, stderr: stderr, cwd: cwd, env: env)
        else
          unknown_command(stderr, "task child #{subcommand}".strip)
        end
      end

      def dispatch_plan(args, stdout:, stderr:, cwd:, env:)
        subcommand = args.shift
        kwargs = { argv: args, stdout: stdout, stderr: stderr, cwd: cwd, env: env }
        case subcommand
        when 'approve' then Internal::Commands::PlanApprove.run(**kwargs)
        when 'status'  then Internal::Commands::PlanStatus.run(**kwargs)
        else
          unknown_command(stderr, "plan #{subcommand}".strip)
        end
      end

      def dispatch_step(args, stdout:, stderr:, cwd:, env:)
        subcommand = args.shift
        kwargs = { argv: args, stdout: stdout, stderr: stderr, cwd: cwd, env: env }
        case subcommand
        when 'start'      then Internal::Commands::StepStart.run(**kwargs)
        when 'complete'   then Internal::Commands::StepComplete.run(**kwargs)
        when 'reopen'     then Internal::Commands::StepReopen.run(**kwargs)
        when 'reset'      then Internal::Commands::StepReset.run(**kwargs)
        when 'skip'       then Internal::Commands::StepSkip.run(**kwargs)
        when 'invocation' then Internal::Commands::StepInvocation.run(**kwargs)
        when 'show'       then Internal::Commands::StepShow.run(**kwargs)
        when 'report'     then Internal::Commands::StepReport.run(**kwargs)
        else
          unknown_command(stderr, "step #{subcommand}".strip)
        end
      end

      def dispatch_task_label(args, stdout:, stderr:, cwd:, env:)
        intercepted = task_subgroup_intercept('label', args, stdout: stdout, stderr: stderr)
        return intercepted if intercepted

        subcommand = args.shift
        kwargs = { argv: args, stdout: stdout, stderr: stderr, cwd: cwd, env: env }
        case subcommand
        when 'add' then Internal::Commands::TaskLabel.add(**kwargs)
        when 'rm'  then Internal::Commands::TaskLabel.rm(**kwargs)
        else
          unknown_command(stderr, "task label #{subcommand}".strip)
        end
      end

      def dispatch_task_dep(args, stdout:, stderr:, cwd:, env:)
        intercepted = task_subgroup_intercept('dep', args, stdout: stdout, stderr: stderr)
        return intercepted if intercepted

        subcommand = args.shift
        kwargs = { argv: args, stdout: stdout, stderr: stderr, cwd: cwd, env: env }
        case subcommand
        when 'add'           then Internal::Commands::TaskDep.add(**kwargs)
        when 'rm', 'remove'  then Internal::Commands::TaskDep.rm(**kwargs)
        when 'list'          then Internal::Commands::TaskDep.list(**kwargs)
        else
          unknown_command(stderr, "task dep #{subcommand}".strip)
        end
      end

      def dispatch_task_index(args, stdout:, stderr:, cwd:, env:)
        intercepted = task_subgroup_intercept('index', args, stdout: stdout, stderr: stderr)
        return intercepted if intercepted

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
