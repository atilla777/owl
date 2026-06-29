# frozen_string_literal: true

require 'owl/version/internal/self_hosted'

RSpec.describe Owl::Version::Internal::SelfHosted do
  describe '.detect' do
    it 'returns true when both owl-cli.gemspec and lib/owl/version.rb exist under root' do
      with_tmp_project do |root|
        write("#{root}/owl-cli.gemspec", "# gemspec\n")
        write("#{root}/lib/owl/version.rb", "module Owl; VERSION = '0.0.0'; end\n")

        expect(described_class.detect(root: root)).to be(true)
      end
    end

    it 'returns false when only owl-cli.gemspec is present' do
      with_tmp_project do |root|
        write("#{root}/owl-cli.gemspec", "# gemspec\n")

        expect(described_class.detect(root: root)).to be(false)
      end
    end

    it 'returns false when only lib/owl/version.rb is present' do
      with_tmp_project do |root|
        write("#{root}/lib/owl/version.rb", "module Owl; VERSION = '0.0.0'; end\n")

        expect(described_class.detect(root: root)).to be(false)
      end
    end

    it 'returns false when neither file is present' do
      with_tmp_project do |root|
        expect(described_class.detect(root: root)).to be(false)
      end
    end
  end
end
