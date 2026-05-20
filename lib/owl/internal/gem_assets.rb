# frozen_string_literal: true

require_relative 'paths'

module Owl
  module Internal
    # Layer-C bootstrap exception #3: gem-shipped assets (bundled JSON schemas,
    # workflow/artifact seed sources, etc.) live in the gem install directory
    # and are not part of any project storage role, so reading them through
    # `Owl::Storage::Api` would be a category error. This module is the
    # canonical place that exception is allowed for non-bootstrap callers.
    #
    # All methods accept an optional `repo_root:` keyword for test seams;
    # production callers omit it and read from the gem install directory.
    module GemAssets
      module_function

      def read(name, repo_root: Paths.repo_root)
        File.read(File.join(repo_root, name.to_s))
      end

      def exist?(name, repo_root: Paths.repo_root)
        File.exist?(File.join(repo_root, name.to_s))
      end

      def directory?(name, repo_root: Paths.repo_root)
        File.directory?(File.join(repo_root, name.to_s))
      end

      # Sorted file paths relative to `dir` itself, walking `dir/**/*`.
      def files_under(dir:, repo_root: Paths.repo_root)
        base = File.join(repo_root, dir.to_s)
        return [] unless File.directory?(base)

        base_with_sep = base.end_with?('/') ? base : "#{base}/"
        Dir.glob(File.join(base, '**', '*'))
           .select { |p| File.file?(p) }
           .sort
           .map { |p| p.delete_prefix(base_with_sep) }
      end

      def subdirectories(dir:, repo_root: Paths.repo_root)
        base = File.join(repo_root, dir.to_s)
        return [] unless File.directory?(base)

        Dir.children(base)
           .select { |name| File.directory?(File.join(base, name)) }
           .sort
      end
    end
  end
end
