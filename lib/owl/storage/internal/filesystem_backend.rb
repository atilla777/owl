# frozen_string_literal: true

require 'fileutils'
require 'pathname'

module Owl
  module Storage
    module Internal
      module FilesystemBackend
        module_function

        def exists?(path)
          Pathname.new(path.to_s).exist?
        end

        def mkdir_p(path)
          FileUtils.mkdir_p(path.to_s)
          Pathname.new(path.to_s)
        end

        def write(path:, contents:)
          pathname = Pathname.new(path.to_s)
          FileUtils.mkdir_p(pathname.dirname.to_s)
          pathname.write(contents)
          pathname
        end

        def read(path)
          Pathname.new(path.to_s).read
        end

        def children(path)
          pathname = Pathname.new(path.to_s)
          return [] unless pathname.directory?

          pathname.children
        end
      end
    end
  end
end
