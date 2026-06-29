# frozen_string_literal: true

require 'pathname'

module Owl
  module Version
    module Internal
      # Detects whether the command is running inside the Owl self-hosted
      # source repository (the checkout that ships the `owl-cli` gem), as
      # opposed to a consumer project where only `.owl/` / `tasks/` / `docs/`
      # are materialized.
      #
      # The signal is the simultaneous presence under `root` of both
      # `owl-cli.gemspec` (the gem name, specific to the source tree) and
      # `lib/owl/version.rb` (the definition of `Owl::VERSION`). Both are
      # required so a stray gemspec in an unrelated tree cannot false-positive.
      # Detection works against the resolved project `root`, not `Dir.pwd`, so
      # running from a subdirectory of the source repository is handled
      # correctly by the caller.
      module SelfHosted
        module_function

        # rubocop:disable Naming/PredicateMethod -- `detect` is the verb fixed
        # by the approved design and used at the call sites in Api.info / specs;
        # a `?` suffix would read oddly for a self-hosted source-tree detector.
        def detect(root:)
          base = Pathname.new(root.to_s)
          File.file?(base.join('owl-cli.gemspec').to_s) &&
            File.file?(base.join('lib', 'owl', 'version.rb').to_s)
        end
        # rubocop:enable Naming/PredicateMethod
      end
    end
  end
end
