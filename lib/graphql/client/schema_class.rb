# frozen_string_literal: true

require "active_support/inflector"
require "graphql"
require "graphql/client/errors"

module GraphQL
  class Client
    module SchemaClass
      def self.generate(schema)
        mod = Module.new
        schema.types.each do |name, type|
          next if name.start_with?("__")
          mod.const_set(name, class_for(type))
        end
        mod
      end

      class NonNullType
        attr_reader :of_klass

        def initialize(of_klass)
          @of_klass = of_klass
        end

        def new(*args)
          @of_klass.new(*args)
        end
      end

      class ListType
        attr_reader :of_klass

        def initialize(of_klass)
          @of_klass = of_klass
        end
      end

      module ObjectType
        def inherited(obj)
          obj.type = self.type
          obj.fields = {}
        end

        def define_field(name, type)
          @fields[name] = type
          method_name = ActiveSupport::Inflector.underscore(name)
          class_eval <<-RUBY, __FILE__, __LINE__+1
            def #{method_name}
              fetch(:#{name})
            end
          RUBY
        end

        module InstanceMethods
          def fetch(name)
            klass = self.class.fields[name]
            klass.new(@data.fetch(name.to_s))
          end

          def to_h
            @data
          end

          def ==(other)
            eql?(other)
          end

          def eql?(other)
            is_a?(other.class) && self.to_h == other.to_h
          end
        end
      end

      module ScalarType
        def new(value)
          if type.respond_to?(:coerce_isolated_input)
            type.coerce_isolated_input(value)
          else
            type.coerce_input(value)
          end
        end
      end

      module InterfaceType
      end

      module EnumType
      end

      module UnionType
      end

      def self.class_for(type)
        @cache ||= {}

        if @cache[type]
          return @cache[type]
        end

        case type
        when GraphQL::InputObjectType
          nil

        when GraphQL::ListType
          @cache[type] = ListType.new(class_for(type.of_type))

        when GraphQL::NonNullType
          @cache[type] = NonNullType.new(class_for(type.of_type))

        when GraphQL::EnumType
          mod = Module.new
          mod.extend(EnumType)

          mod.instance_eval <<-RUBY
            class << self
              attr_accessor :type
            end
          RUBY

          mod.type = type

          type.values.keys.each do |value|
            mod.const_set(value, value)
          end

          @cache[type] = mod

        when GraphQL::UnionType
          mod = Module.new
          mod.extend(UnionType)

          mod.instance_eval <<-RUBY
            class << self
              attr_accessor :type
            end
          RUBY

          mod.type = type

          @cache[type] = mod

        when GraphQL::ScalarType
          klass = Class.new
          klass.extend(ScalarType)

          klass.instance_eval <<-RUBY
            class << self
              attr_accessor :type
            end
          RUBY

          klass.type = type

          @cache[type] = klass
        when GraphQL::InterfaceType
          mod = Module.new
          mod.extend(InterfaceType)

          mod.instance_eval <<-RUBY
            class << self
              attr_accessor :type
            end
          RUBY

          mod.type = type

          @cache[type] = mod
        when GraphQL::ObjectType
          klass = Class.new
          klass.extend(ObjectType)
          klass.send :include, ObjectType::InstanceMethods

          klass.instance_eval <<-RUBY
            class << self
              attr_accessor :type, :fields
            end
          RUBY

          klass.type = type
          klass.fields = {}

          klass.class_eval <<-RUBY
            def initialize(data = {})
              @data = data
            end
          RUBY

          @cache[type] = klass

          type.interfaces.each do |interface|
            klass.send :include, class_for(interface)
          end

          type.all_fields.each do |field|
            klass.fields[field.name.to_sym] = class_for(field.type)
          end

          klass
        else
          raise TypeError, "unexpected #{type.class}"
        end
      end
    end
  end
end
