# frozen_string_literal: true

require_relative '../version'
require_relative 'internal/commands/config_validate'
require_relative 'internal/commands/init'
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
          subcommand = args.shift
          case subcommand
          when 'list'
            Internal::Commands::WorkflowList.run(argv: args, stdout: stdout, stderr: stderr, cwd: cwd, env: env)
          else
            unknown_command(stderr, "workflow #{subcommand}".strip)
          end
        when 'config'
          subcommand = args.shift
          case subcommand
          when 'validate'
            Internal::Commands::ConfigValidate.run(argv: args, stdout: stdout, stderr: stderr, cwd: cwd, env: env)
          else
            unknown_command(stderr, "config #{subcommand}".strip)
          end
        else
          unknown_command(stderr, command)
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
