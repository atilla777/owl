# frozen_string_literal: true

require 'json'
require 'yaml'

require_relative '../../result'

module Owl
  module Subagents
    module Internal
      # Lightweight validator for a subagent report body. The body is
      # markdown-with-frontmatter (RFC #1 §4.3, knowledge entry 46):
      #
      #     ---
      #     status: returned_normally|do_not_use|error
      #     summary: "<one-line>"
      #     session_type: discussion|execution
      #     ---
      #
      #     ## Result
      #     ...
      #
      # The canonical contract lives in `schemas/step_report.json` (RFC #1 §4.3
      # publishes this schema). This module loads that schema once per process
      # and derives ALLOWED_STATUSES, the required frontmatter keys, and the
      # required H2 sections from it; OutputSpec.validate parses the body and
      # reports missing pieces as a structured error result.
      module OutputSpec
        SCHEMA_PATH = File.expand_path('../../../../schemas/step_report.json', __dir__)

        def self.deep_freeze(value)
          case value
          when Hash
            value.each_value { |v| deep_freeze(v) }
            value.freeze
          when Array
            value.each { |v| deep_freeze(v) }
            value.freeze
          else
            value.respond_to?(:freeze) ? value.freeze : value
          end
        end

        def self.load_schema!
          raw = File.read(SCHEMA_PATH)
          parsed = JSON.parse(raw)
          deep_freeze(parsed)
        rescue Errno::ENOENT, JSON::ParserError => e
          raise 'Owl::Subagents::Internal::OutputSpec: cannot load step_report schema ' \
                "from #{SCHEMA_PATH}: #{e.class}: #{e.message}"
        end

        SCHEMA = load_schema!
        ALLOWED_STATUSES = SCHEMA.dig('properties', 'status', 'enum').dup.freeze
        DEFAULT_REQUIRED_FRONTMATTER_KEYS = SCHEMA['required'].dup.freeze
        DEFAULT_REQUIRED_SECTIONS = SCHEMA['x-required-sections'].dup.freeze

        module_function

        # @return [Hash] frozen copy of `schemas/step_report.json` (parsed JSON).
        def schema
          SCHEMA
        end

        # @return [Hash] { required_frontmatter_keys: [...], required_sections: [...] }
        def default
          {
            required_frontmatter_keys: DEFAULT_REQUIRED_FRONTMATTER_KEYS,
            required_sections: DEFAULT_REQUIRED_SECTIONS
          }
        end

        # Parse `report_body` (a markdown-with-frontmatter string) and
        # validate it against `output_spec`. Returns a Result with the
        # parsed `{ frontmatter:, sections: }` payload on success.
        def validate(report_body, output_spec: nil)
          spec = output_spec || default
          unless report_body.is_a?(String) && !report_body.empty?
            return Result.err(
              code: :report_empty,
              message: 'Report body must be a non-empty markdown-with-frontmatter string.'
            )
          end

          parts = split_frontmatter(report_body)
          return parts if parts.is_a?(Owl::Result::Err)

          frontmatter, body = parts

          errors = []
          errors.concat(check_required_keys(frontmatter, Array(spec[:required_frontmatter_keys])))
          errors.concat(check_status(frontmatter))
          sections = section_headings(body)
          errors.concat(check_required_sections(sections, Array(spec[:required_sections])))

          return Result.ok(frontmatter: frontmatter, sections: sections) if errors.empty?

          Result.err(code: :report_invalid, message: 'Report failed output_spec validation.',
                     details: { errors: errors })
        end

        def split_frontmatter(body)
          unless body.start_with?("---\n")
            return Result.err(
              code: :missing_frontmatter,
              message: 'Report body must start with a YAML frontmatter block.'
            )
          end

          end_idx = body.index("\n---\n", 4)
          if end_idx.nil?
            return Result.err(
              code: :unterminated_frontmatter,
              message: 'YAML frontmatter block is not terminated by `---` on its own line.'
            )
          end

          yaml_segment = body[4..end_idx - 1]
          markdown_segment = body[(end_idx + 5)..] || ''

          frontmatter = begin
            YAML.safe_load(yaml_segment) || {}
          rescue Psych::SyntaxError => e
            return Result.err(
              code: :invalid_frontmatter_yaml,
              message: "Frontmatter YAML is invalid: #{e.message}"
            )
          end

          unless frontmatter.is_a?(Hash)
            return Result.err(
              code: :invalid_frontmatter_yaml,
              message: 'Frontmatter must be a YAML mapping.'
            )
          end

          [frontmatter, markdown_segment]
        end

        def check_required_keys(frontmatter, required_keys)
          required_keys.each_with_object([]) do |key, errors|
            value = frontmatter[key.to_s]
            if value.nil? || value.to_s.strip.empty?
              errors << { path: "frontmatter/#{key}",
                          message: "key `#{key}` is required." }
            end
          end
        end

        def check_status(frontmatter)
          status = frontmatter['status']
          return [] if status.nil? || ALLOWED_STATUSES.include?(status.to_s)

          [{
            path: 'frontmatter/status',
            message: "status must be one of #{ALLOWED_STATUSES.inspect} (got #{status.inspect})."
          }]
        end

        def section_headings(body)
          body.scan(/^##\s+(.+?)\s*$/).flatten
        end

        def check_required_sections(sections, required)
          missing = required - sections
          missing.map do |name|
            { path: "sections/#{name}", message: "required `## #{name}` section is missing." }
          end
        end

        private_class_method :split_frontmatter, :check_required_keys, :check_status,
                             :section_headings, :check_required_sections
      end
    end
  end
end
