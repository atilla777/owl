# frozen_string_literal: true

module Owl
  module Internal
    module Paths
      module_function

      OWL_REPO_ROOT = File.expand_path('../../..', __dir__)

      def repo_root
        OWL_REPO_ROOT
      end

      def schemas_dir
        File.join(OWL_REPO_ROOT, 'schemas')
      end
    end
  end
end
