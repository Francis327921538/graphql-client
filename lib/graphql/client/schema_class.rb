# frozen_string_literal: true

require "active_support/inflector"
require "graphql"
require "graphql/client/errors"

module GraphQL
  class Client
    module SchemaClass
      class UnfetchedFieldError < Error; end

      class Base
        def fetch(name)
          cast(self.class.type.get_field(name.to_s).type, @data.fetch(name.to_s) {
            raise UnfetchedFieldError, "unfetched field `#{name}' on #{self.class} type. https://git.io/v1y3U"
          })
        end

        def cast(type, value)
          case type.unwrap
          when GraphQL::ScalarType
            if type.respond_to?(:coerce_isolated_input)
              type.coerce_isolated_input(value)
            else
              type.coerce_input(value)
            end
          when GraphQL::ObjectType
            SchemaClass.class_for(type.unwrap).new(value)
          else
            raise TypeError, "unknown type #{type.unwrap.class}"
          end
        end
      end

      def self.generate(schema)
        mod = Module.new
        schema.types.each do |name, type|
          next if name.start_with?("__")
          mod.const_set(name, class_for(type))
        end
        mod
      end

      def self.class_for(type)
        @cache ||= {}

        if @cache[type]
          return @cache[type]
        end

        case type
        when GraphQL::ScalarType
          nil
        when GraphQL::InterfaceType
          mod = Module.new

          mod.instance_eval <<-RUBY
            class << self
              attr_accessor :type
            end
          RUBY

          mod.type = type

          type.fields.each do |name, field|
            method_name = ActiveSupport::Inflector.underscore(name)
            mod.class_eval <<-RUBY, __FILE__, __LINE__+1
              def #{method_name}
                fetch(:#{name})
              end
            RUBY
          end

          @cache[type] = mod
        when GraphQL::ObjectType
          klass = Class.new(Base)

          klass.instance_eval <<-RUBY
            class << self
              attr_accessor :type
            end
          RUBY

          klass.type = type

          klass.class_eval <<-RUBY
            def initialize(data = {})
              @data = data
            end
          RUBY

          type.interfaces.each do |interface|
            klass.send :include, class_for(interface)
          end

          type.fields.each do |name, field|
            method_name = ActiveSupport::Inflector.underscore(name)
            klass.class_eval <<-RUBY, __FILE__, __LINE__+1
              def #{method_name}
                fetch(:#{name})
              end
            RUBY
          end

          @cache[type] = klass
        else
          raise TypeError, "unexpected #{type.class}"
        end
      end
    end
  end
end
