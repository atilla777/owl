# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'yaml'

module Owl
  module Config
    module Internal
      module Serializer
        CONFIG_PATH = '.owl/config.yaml'

        module_function

        def dump(raw_hash)
          YAML.dump(raw_hash)
        end

        def write_atomic(root:, raw_hash:)
          target = Pathname.new(root.to_s) + CONFIG_PATH
          FileUtils.mkdir_p(target.dirname.to_s)
          tmp = Pathname.new("#{target}.tmp.#{Process.pid}.#{rand(10_000)}")
          tmp.write(dump(raw_hash))
          File.rename(tmp.to_s, target.to_s)
          target
        ensure
          tmp.delete if tmp && tmp.exist? && tmp != target
        end
      end
    end
  end
end
