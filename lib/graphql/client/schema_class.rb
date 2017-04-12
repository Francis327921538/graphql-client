# frozen_string_literal: true

require "active_support/inflector"
require "graphql"
require "graphql/client/deprecation"
require "graphql/client/errors"

module GraphQL
  class Client
    module SchemaClass
      def self.generate(schema)
        mod = Module.new
        cache = {}
        schema.types.each do |name, type|
          next if name.start_with?("__")
          mod.const_set(name, class_for(type, cache))
        end
        mod
      end

      class NonNullType
        attr_reader :of_klass

        def initialize(of_klass)
          @of_klass = of_klass
        end

        def cast(value)
          @of_klass.cast(value)
        end

        def inspect
          "#{of_klass.inspect}!"
        end
      end

      class ListType
        attr_reader :of_klass

        def initialize(of_klass)
          @of_klass = of_klass
        end

        def cast(values)
          case values
          when Array
            values.map { |value| @of_klass.cast(value) }
          else
            nil
          end
        end

        def inspect
          "[#{of_klass.inspect}]"
        end
      end

      class PossibleTypes
        def initialize(types)
          @possible_types = types
        end

        def cast(value)
          typename = value && value["__typename"]
          if type = @possible_types[typename]
            type.cast(value)
          else
            nil
          end
        end
      end

      module EnumType
        def self.new(type)
          mod = Module.new
          mod.extend(EnumType)

          mod.type = type

          type.values.keys.each do |value|
            mod.const_set(value, value)
          end

          mod
        end

        attr_accessor :type

        def cast(value)
          value
        end
      end


      module InterfaceType
        def self.new(type)
          mod = Module.new
          mod.extend(InterfaceType)
          mod.type = type
          mod
        end

        attr_accessor :type

        def new(types)
          PossibleTypes.new(types)
        end
      end

      module UnionType
        def self.new(type)
          mod = Module.new
          mod.extend(UnionType)
          mod.type = type
          mod
        end

        attr_accessor :type

        def new(types)
          PossibleTypes.new(types)
        end
      end

      class ScalarType
        def self.new(type)
          klass = Class.new(ScalarType)
          klass.type = type
          klass
        end

        class << self
          attr_accessor :type
        end

        def self.cast(value)
          if value
            if type.respond_to?(:coerce_isolated_input)
              type.coerce_isolated_input(value)
            else
              type.coerce_input(value)
            end
          else
            nil
          end
        end
      end

      module ObjectType
        def self.new(type)
          klass = Class.new(InstanceMethods)
          klass.extend(ObjectType)
          klass.type = type
          klass
        end

        def inherited(obj)
          obj.type = self.type
        end

        def define_field(name, type)
          method_name = ActiveSupport::Inflector.underscore(name)
          define_method(method_name) do
            type.cast(@data.fetch(name.to_s))
          end

          if name != method_name
            define_method(name) do
              type.cast(@data.fetch(name.to_s))
            end
            Deprecation.deprecate_methods(self, name => "Use ##{method_name} instead")
          end
        end

        attr_accessor :type, :fields

        def cast(value)
          new(value)
        end

        class InstanceMethods
          def initialize(data = {})
            @data = data
          end
        end
      end


      def self.class_for(type, cache)
        if cache[type]
          return cache[type]
        end

        case type
        when GraphQL::InputObjectType
          nil
        when GraphQL::ScalarType
          cache[type] = ScalarType.new(type)
        when GraphQL::EnumType
          cache[type] = EnumType.new(type)
        when GraphQL::ListType
          cache[type] = ListType.new(class_for(type.of_type, cache))
        when GraphQL::NonNullType
          cache[type] = NonNullType.new(class_for(type.of_type, cache))
        when GraphQL::UnionType
          cache[type] = UnionType.new(type)
        when GraphQL::InterfaceType
          cache[type] = InterfaceType.new(type)
        when GraphQL::ObjectType
          cache[type] = klass = ObjectType.new(type)

          type.interfaces.each do |interface|
            klass.send :include, class_for(interface, cache)
          end

          klass.fields = {}
          type.all_fields.each do |field|
            klass.fields[field.name.to_sym] = class_for(field.type, cache)
          end

          klass
        else
          raise TypeError, "unexpected #{type.class}"
        end
      end
    end
  end
end
