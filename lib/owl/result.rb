# frozen_string_literal: true

module Owl
  module Result
    Ok = Data.define(:value) do
      def ok?
        true
      end

      def err?
        false
      end
    end

    Err = Data.define(:code, :message, :details) do
      def ok?
        false
      end

      def err?
        true
      end
    end

    def self.ok(value)
      Ok.new(value: value)
    end

    def self.err(code:, message:, details: {})
      Err.new(code: code, message: message, details: details)
    end
  end
end
