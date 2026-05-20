# frozen_string_literal: true

require_relative 'gem_assets'
require_relative 'paths'

module Owl
  module Internal
    module SeededLoader
      module_function

      def load(source_dir:, target_prefix:, repo_root: Paths.repo_root)
        return [] unless GemAssets.directory?(source_dir, repo_root: repo_root)

        GemAssets.files_under(dir: source_dir, repo_root: repo_root).map do |rel|
          target = target_prefix.empty? ? rel : [target_prefix, rel].join('/')
          contents = GemAssets.read([source_dir, rel].join('/'), repo_root: repo_root)
          { relative_path: target, contents: contents }
        end
      end

      def subdirectories(source_dir:, repo_root: Paths.repo_root)
        GemAssets.subdirectories(dir: source_dir, repo_root: repo_root)
      end
    end
  end
end
