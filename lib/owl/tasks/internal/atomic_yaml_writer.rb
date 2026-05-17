# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'securerandom'
require 'yaml'

module Owl
  module Tasks
    module Internal
      module AtomicYamlWriter
        module_function

        def write(path:, payload:)
          target = Pathname.new(path.to_s)
          FileUtils.mkdir_p(target.dirname.to_s)

          tmp = target.dirname.join(".#{target.basename}.tmp.#{Process.pid}.#{SecureRandom.hex(4)}")
          tmp.write(YAML.dump(stringify_keys(payload)))
          File.rename(tmp.to_s, target.to_s)
          target
        ensure
          tmp&.delete if tmp&.exist?
        end

        def stringify_keys(value)
          case value
          when Hash
            value.each_with_object({}) { |(k, v), memo| memo[k.to_s] = stringify_keys(v) }
          when Array
            value.map { |v| stringify_keys(v) }
          else
            value
          end
        end
      end
    end
  end
end
