# frozen_string_literal: true

require_relative 'paths'

module Owl
  module Internal
    module SeededLoader
      module_function

      def load(source_dir:, target_prefix:, repo_root: Paths.repo_root)
        base = File.join(repo_root, source_dir)
        return [] unless Dir.exist?(base)

        base_with_sep = base.end_with?('/') ? base : "#{base}/"
        Dir.glob(File.join(base, '**', '*'))
           .select { |p| File.file?(p) }
           .sort
           .map do |path|
             rel = path.delete_prefix(base_with_sep)
             target = target_prefix.empty? ? rel : File.join(target_prefix, rel)
             { relative_path: target, contents: File.read(path) }
           end
      end

      def subdirectories(source_dir:, repo_root: Paths.repo_root)
        base = File.join(repo_root, source_dir)
        return [] unless Dir.exist?(base)

        Dir.children(base)
           .select { |name| File.directory?(File.join(base, name)) }
           .sort
      end
    end
  end
end
