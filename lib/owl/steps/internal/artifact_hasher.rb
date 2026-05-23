# frozen_string_literal: true

require 'digest'
require 'pathname'

require_relative '../../result'

module Owl
  module Steps
    module Internal
      module ArtifactHasher
        module_function

        def call(path:)
          pathname = Pathname.new(path.to_s)
          unless pathname.file?
            return Result.err(
              code: :artifact_missing,
              message: "Artifact file does not exist: #{pathname}.",
              details: { path: pathname.to_s }
            )
          end

          Result.ok(Digest::SHA256.hexdigest(pathname.binread))
        end
      end
    end
  end
end
