# frozen_string_literal: true

require 'pathname'
require 'yaml'

require_relative '../../result'
require_relative 'source_loader'

module Owl
  module Artifacts
    module Internal
      module ArtifactTypeLoader
        ARTIFACT_DIR = 'artifacts'

        module_function

        def load(root:, type_key:, registry_entry:)
          source = registry_entry && registry_entry[:source]
          source_info = SourceLoader.load(root: root, source: source)

          unless source_info[:present]
            return Result.err(
              code: :artifact_type_source_missing,
              message: "Artifact type '#{type_key}' source not present.",
              details: { type: type_key.to_s, source: source, source_path: source_info[:source_path] }
            )
          end

          body = source_info[:body] || {}
          control_root = Pathname.new(root.to_s) + '.owl'
          artifact_dir = control_root + ARTIFACT_DIR + type_key.to_s
          template_rel = body['default_template'] || body[:default_template]

          template_path = template_rel ? (artifact_dir + template_rel.to_s) : nil
          template_present = template_path ? template_path.exist? : false

          Result.ok(
            type: type_key.to_s,
            source_path: source_info[:source_path],
            body: body,
            template_path: template_path&.to_s,
            template_present: template_present,
            validation: body['validation'] || {},
            front_matter: body['front_matter'] || {},
            agent_hints: body['agent_hints'] || {},
            title: body['title'],
            kind: body['kind'],
            description: body['description']
          )
        end
      end
    end
  end
end
