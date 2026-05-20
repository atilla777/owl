# frozen_string_literal: true

require 'pathname'
require 'yaml'

require_relative '../result'
require_relative '../artifacts/backends/filesystem'
require_relative '../config/backends/filesystem'
require_relative '../publish/backends/filesystem'
require_relative '../storage/backends/filesystem'
require_relative '../tasks/backends/filesystem'
require_relative '../validation/backends/filesystem'
require_relative '../workflows/backends/filesystem'

module Owl
  module Internal
    # Resolves the active backend for a domain `scope` from `.owl/config.yaml`.
    #
    # Layer-C bootstrap exception #1: `read_backend_name` reads `.owl/config.yaml`
    # directly via `Pathname#read` + `YAML.safe_load` instead of going through
    # `Owl::Config::Api` / `Owl::Storage::Api`. The reason is structural —
    # selecting the storage (or any other) backend depends on the config file,
    # so routing the config read through a backend would create an unresolvable
    # chicken-and-egg cycle. This file is the canonical place that exception is
    # allowed; new callers should not replicate raw FS reads outside of this
    # resolver.
    #
    # Layer-C bootstrap exception #2: `scope: :config` always resolves to
    # `Owl::Config::Backends::Filesystem`, regardless of `settings.storage.backend`.
    # The config domain *is* the bootstrap — it has to be readable before any
    # backend selector can run, so a non-FS config backend would re-create the
    # same cycle as exception #1. This also keeps `Owl::Config::Api.validate`
    # able to surface schema errors (e.g. `unsupported_settings_storage_backend`)
    # instead of failing earlier with `:unknown_backend`.
    #
    # Layer-C bootstrap exception #3: gem-shipped assets (bundled JSON schemas,
    # workflow/artifact seed sources, etc.) are read by `Owl::Internal::GemAssets`
    # rather than `Owl::Storage::Api`. Those files live in the gem install
    # directory, not in any project storage role, so routing them through a
    # storage backend would be a category error. `Owl::Validation::Internal::
    # SchemaCheck` is the first caller; non-bootstrap modules that need to read
    # bundled gem assets should funnel through `GemAssets` instead of replicating
    # raw `File.read` on absolute paths.
    module BackendResolver
      module_function

      def resolve(root:, scope:)
        # Layer-C exception #2 (see module header): Config domain is the
        # bootstrap and is always served by the Filesystem backend.
        return Owl::Result.ok(filesystem_backend(scope: scope, root: root)) if scope == :config

        backend_name = read_backend_name(root: root)
        case backend_name
        when nil, 'filesystem'
          Owl::Result.ok(filesystem_backend(scope: scope, root: root))
        else
          Owl::Result.err(
            code: :unknown_backend,
            message: "Unknown Owl #{scope} backend: #{backend_name.inspect}",
            details: { scope: scope, backend_name: backend_name }
          )
        end
      end

      def filesystem_backend(scope:, root:)
        case scope
        when :artifacts  then Owl::Artifacts::Backends::Filesystem.new(root: root)
        when :config     then Owl::Config::Backends::Filesystem.new(root: root)
        when :publish    then Owl::Publish::Backends::Filesystem.new(root: root)
        when :storage    then Owl::Storage::Backends::Filesystem.new(root: root)
        when :tasks      then Owl::Tasks::Backends::Filesystem.new(root: root)
        when :validation then Owl::Validation::Backends::Filesystem.new(root: root)
        when :workflows  then Owl::Workflows::Backends::Filesystem.new(root: root)
        else
          raise ArgumentError, "Unknown BackendResolver scope: #{scope.inspect}"
        end
      end

      # Layer-C bootstrap exception (see module header): selects the configured
      # backend by reading `.owl/config.yaml` from the filesystem directly,
      # without routing through `Owl::Storage::Api`.
      def read_backend_name(root:)
        config_path = Pathname.new(root.to_s) + '.owl/config.yaml'
        return nil unless config_path.exist?

        raw = YAML.safe_load(config_path.read, aliases: false)
        return nil unless raw.is_a?(Hash)

        settings = raw['settings']
        return nil unless settings.is_a?(Hash)

        storage = settings['storage']
        return nil unless storage.is_a?(Hash)

        backend = storage['backend']
        backend.is_a?(String) && !backend.empty? ? backend : nil
      rescue Psych::SyntaxError
        nil
      end
    end
  end
end
