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
    # v1 exposes only `read(name)`. Glob / list support over gem assets will
    # land in the broader gem-assets cleanup (see the small-domain direct FS
    # cleanup subtask under `Owl: extend Backend pattern to all domains`).
    module GemAssets
      module_function

      def read(name)
        File.read(File.join(Owl::Internal::Paths.repo_root, name.to_s))
      end
    end
  end
end
