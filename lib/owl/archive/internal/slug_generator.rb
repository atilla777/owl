# frozen_string_literal: true

module Owl
  module Archive
    module Internal
      module SlugGenerator
        FALLBACK = 'task'
        MAX_LENGTH = 60

        module_function

        def from(title)
          base = title.to_s.downcase
          normalized = base.gsub(/[^a-z0-9]+/, '-').squeeze('-')
          normalized = normalized.sub(/\A-+/, '').sub(/-+\z/, '')

          return FALLBACK if normalized.empty?

          truncate(normalized)
        end

        def truncate(slug)
          return slug if slug.length <= MAX_LENGTH

          cut = slug[0, MAX_LENGTH]
          last_dash = cut.rindex('-')
          cut = cut[0, last_dash] if last_dash&.positive?
          cut.sub(/-+\z/, '')
        end
      end
    end
  end
end
