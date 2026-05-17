# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'tmpdir'

module TmpProject
  module_function

  def with_tmp_project
    Dir.mktmpdir('owl-spec-') do |dir|
      yield Pathname.new(dir)
    end
  end

  def write(path, contents)
    pathname = Pathname.new(path.to_s)
    FileUtils.mkdir_p(pathname.dirname.to_s)
    pathname.write(contents)
    pathname
  end
end

RSpec.configure do |config|
  config.include TmpProject
end
