# frozen_string_literal: true

module Owl
  module Config
    module Internal
      Document = Data.define(
        :schema_version,
        :project,
        :owl_section,
        :workflow,
        :storage,
        :raw
      ) do
        def active_profile_name
          storage.fetch('active_profile')
        end

        def active_profile
          storage.fetch('profiles').fetch(active_profile_name)
        end
      end
    end
  end
end
