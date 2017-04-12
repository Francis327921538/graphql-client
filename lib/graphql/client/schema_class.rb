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
          mod.const_set(name, class_for(schema, type, cache))
        end
        mod
      end

      class NonNullType
        def initialize(of_klass)
          @of_klass = of_klass
        end

        attr_reader :of_klass

        def cast(value, errors)
          @of_klass.cast(value, errors)
        end

        def inspect
          "#{of_klass.inspect}!"
        end

        # XXX: Remove type merging
        def |(other)
          if self.class == other.class
            self.of_klass | other.of_klass
          else
            raise TypeError, "expected other to be a #{self.class}"
          end
        end
      end

      class ListType
        def initialize(of_klass)
          @of_klass = of_klass
        end

        attr_reader :of_klass

        def cast(values, errors)
          case values
          when Array
            List.new(values.each_with_index.map { |e, idx|
              @of_klass.cast(e, errors.filter_by_path(idx))
            }, errors)
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

        def cast(value, errors)
          typename = value && value["__typename"]
          if type = @possible_types[typename]
            type.cast(value, errors)
          else
            nil
          end
        end
      end

      class TypeModule < Module
        def initialize(type)
          @type = type
        end

        attr_reader :type
      end

      class EnumType < TypeModule
        def initialize(type)
          super(type)

          type.values.keys.each do |value|
            const_set(value, value)
          end
        end

        def cast(value, _errors = nil)
          value
        end
      end

      class ScalarType < TypeModule
        def cast(value, _errors = nil)
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

        # XXX: Remove type merging
        def |(*)
          self
        end
      end

      class InterfaceType < TypeModule
      end

      class UnionType < TypeModule
      end

      class ObjectType < TypeModule
        attr_accessor :fields

        def included(base)
          base.extend(ClassMethods)
          base.send :include, InstanceMethods
          base.type = self.type
        end

        module ClassMethods
          def define_field(name, type)
            method_name = ActiveSupport::Inflector.underscore(name)
            define_method(method_name) do
              type.cast(@data.fetch(name.to_s), @errors.filter_by_path(name.to_s))
            end

            define_method("#{method_name}?") do
              @data.fetch(name.to_s) ? true : false
            end

            if name != method_name
              define_method(name) do
                type.cast(@data.fetch(name.to_s), @errors.filter_by_path(name.to_s))
              end
              Deprecation.deprecate_methods(self, name => "Use ##{method_name} instead")
            end
          end

          attr_accessor :type

          def cast(value, errors)
            new(value, errors)
          end
        end

        module InstanceMethods
          def initialize(data = {}, errors = Errors.new)
            @data = data
            @errors = errors
          end

          def to_h
            @data
          end

          # Public: Return errors associated with data.
          #
          # Returns Errors collection.
          attr_reader :errors

          def inspect
            parent = self.class.ancestors.select { |m| m.is_a?(ObjectType) }.last

            ivars = @data.map { |key, value|
              if value.is_a?(Hash) || value.is_a?(Array)
                "#{key}=..."
              else
                "#{key}=#{value.inspect}"
              end
            }

            buf = "#<#{parent.name}".dup
            buf << " " << ivars.join(" ") if ivars.any?
            buf << ">"
            buf
          end

          def typename
            Deprecation.deprecation_warning("typename", "Use #class.type.name instead")
            self.class.type.name
          end

          def type_of?(*types)
            Deprecation.deprecation_warning("type_of?", "Use #is_a? instead")
            names = ([self.class.type] + self.class.ancestors.select { |m| m.is_a?(TypeModule) }.map(&:type)).map(&:name)
            types.any? { |type| names.include?(type.to_s) }
          end
        end
      end


      def self.class_for(schema, type, cache)
        return cache[type] if cache[type]

        case type
        when GraphQL::InputObjectType
          nil
        when GraphQL::ScalarType
          cache[type] = ScalarType.new(type)
        when GraphQL::EnumType
          cache[type] = EnumType.new(type)
        when GraphQL::ListType
          cache[type] = ListType.new(class_for(schema, type.of_type, cache))
        when GraphQL::NonNullType
          cache[type] = NonNullType.new(class_for(schema, type.of_type, cache))
        when GraphQL::UnionType
          cache[type] = UnionType.new(type)
        when GraphQL::InterfaceType
          cache[type] = InterfaceType.new(type)
        when GraphQL::ObjectType
          cache[type] = klass = ObjectType.new(type)

          type.interfaces.each do |interface|
            klass.send :include, class_for(schema, interface, cache)
          end

          klass.fields = {}
          type.all_fields.each do |field|
            klass.fields[field.name.to_sym] = class_for(schema, field.type, cache)
          end

          klass
        else
          raise TypeError, "unexpected #{type.class}"
        end
      end
    end
  end
end
