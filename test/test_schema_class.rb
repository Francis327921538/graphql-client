# frozen_string_literal: true
require "graphql"
require "graphql/client/schema_class"
require "minitest/autorun"
require "time"

class TestSchemaType < MiniTest::Test
  DateTime = GraphQL::ScalarType.define do
    name "DateTime"
    coerce_input ->(value, *) do
      Time.iso8601(value)
    end
    coerce_result ->(value, *) do
      value.utc.iso8601
    end
  end

  NodeArgInput = GraphQL::InputObjectType.define do
    name "NodeInput"
    argument :id, !types.String
  end

  NodeType = GraphQL::InterfaceType.define do
    name "Node"
    field :id, !types.ID do
      argument :input, NodeArgInput
    end
  end

  PlanEnum = GraphQL::EnumType.define do
    name "Plan"
    value "FREE"
    value "SMALL"
    value "LARGE"
  end

  PersonType = GraphQL::ObjectType.define do
    name "Person"
    interfaces [NodeType]
    field :name, !types.String
    field :firstName, !types.String
    field :lastName, !types.String
    field :age, !types.Int
    field :birthday, !DateTime
    field :friends, !types[!PersonType]
    field :plan, !PlanEnum
  end

  PhotoType = GraphQL::ObjectType.define do
    name "Photo"
    field :height, !types.Int
    field :width, !types.Int
  end

  SearchResultUnion = GraphQL::UnionType.define do
    name "SearchResult"
    possible_types [PersonType, PhotoType]
  end

  QueryType = GraphQL::ObjectType.define do
    name "Query"
    field :me, !PersonType
    field :node, NodeType
    field :firstSearchResult, !SearchResultUnion
  end

  Schema = GraphQL::Schema.define(query: QueryType) do
    resolve_type ->(_obj, _ctx) { raise NotImplementedError }
  end

  Types = GraphQL::Client::SchemaClass.generate(Schema)

  def test_query_object_class
    assert_kind_of GraphQL::Client::SchemaClass::ObjectType, Types::Query
    assert_equal Class, Types::Query.class
    assert_equal QueryType, Types::Query.type
  end

  def test_person_object_class
    assert_kind_of GraphQL::Client::SchemaClass::ObjectType, Types::Person
    assert_equal Class, Types::Person.class
    assert Types::Person < Types::Node
    assert_equal PersonType, Types::Person.type
  end

  def test_id_scalar_object
    assert_kind_of GraphQL::Client::SchemaClass::ScalarType, Types::ID
    assert_equal Class, Types::ID.class
    assert_equal GraphQL::ID_TYPE, Types::ID.type
  end

  def test_string_scalar_object
    assert_kind_of GraphQL::Client::SchemaClass::ScalarType, Types::String
    assert_equal Class, Types::String.class
    assert_equal GraphQL::STRING_TYPE, Types::String.type
  end

  def test_int_scalar_object
    assert_kind_of GraphQL::Client::SchemaClass::ScalarType, Types::Int
    assert_equal Class, Types::Int.class
    assert_equal GraphQL::INT_TYPE, Types::Int.type
  end

  def test_datetime_scalar_object
    assert_kind_of GraphQL::Client::SchemaClass::ScalarType, Types::DateTime
    assert_equal Class, Types::DateTime.class
    assert_equal DateTime, Types::DateTime.type
  end

  def test_boolean_scalar_object
    assert_kind_of GraphQL::Client::SchemaClass::ScalarType, Types::Boolean
    assert_equal Class, Types::Boolean.class
    assert_equal GraphQL::BOOLEAN_TYPE, Types::Boolean.type
  end

  def test_node_interface_module
    assert_kind_of GraphQL::Client::SchemaClass::InterfaceType, Types::Node
    assert_equal Module, Types::Node.class
    assert_equal NodeType, Types::Node.type
  end

  def test_search_result_union
    assert_kind_of GraphQL::Client::SchemaClass::UnionType, Types::SearchResult
    assert_equal Module, Types::SearchResult.class
    assert_equal SearchResultUnion, Types::SearchResult.type
  end

  def test_plan_enum_constants
    assert_kind_of GraphQL::Client::SchemaClass::EnumType, Types::Plan
    assert_equal Module, Types::Plan.class
    assert_equal PlanEnum, Types::Plan.type

    assert_equal "FREE", Types::Plan::FREE
    assert_equal "SMALL", Types::Plan::SMALL
    assert_equal "LARGE", Types::Plan::LARGE
  end

  def test_person_fields
    assert_kind_of GraphQL::Client::SchemaClass::NonNullType, Types::Person.fields[:name]
    assert_equal Types::String, Types::Person.fields[:name].of_klass

    assert_kind_of GraphQL::Client::SchemaClass::NonNullType, Types::Person.fields[:friends]
    assert_kind_of GraphQL::Client::SchemaClass::ListType, Types::Person.fields[:friends].of_klass
    assert_kind_of GraphQL::Client::SchemaClass::NonNullType, Types::Person.fields[:friends].of_klass.of_klass
    assert_kind_of GraphQL::Client::SchemaClass::ObjectType, Types::Person.fields[:friends].of_klass.of_klass.of_klass
    assert_equal Types::Person, Types::Person.fields[:friends].of_klass.of_klass.of_klass
  end

  def test_query_object_subclass
    query_klass = Class.new(Types::Query)
    person_klass = Class.new(Types::Person)

    query_klass.define_field :me, :me, person_klass
    assert_includes query_klass.instance_methods, :me

    person_klass.define_field :id, :id
    assert_includes person_klass.instance_methods, :id

    assert query = query_klass.new({
      "me" => {
        "id" => "1"
      }
    })

    assert_kind_of Types::Person, query.me
    assert_kind_of person_klass, query.me
    assert_equal "1", query.me.id

    assert_raises NoMethodError do
      query.todo
    end
  end

  def test_person_object_subclass
    person_klass = Class.new(Types::Person)

    person_klass.define_field :id, :id
    person_klass.define_field :name, :name
    person_klass.define_field :first_name, :firstName
    person_klass.define_field :last_name, :lastName
    person_klass.define_field :birthday, :birthday

    assert_includes person_klass.instance_methods, :id
    assert_includes person_klass.instance_methods, :name
    assert_includes person_klass.instance_methods, :first_name
    assert_includes person_klass.instance_methods, :last_name
    refute_includes person_klass.instance_methods, :lastName

    assert person = person_klass.new({
      "id" => "1",
      "name" => "Josh",
      "firstName" => "Joshua",
      "lastName" => "Peek",
      "birthday" => Time.at(0).iso8601
    })

    assert_equal "1", person.id
    assert_equal "Josh", person.name
    assert_equal "Joshua", person.first_name
    assert_equal "Peek", person.last_name
    assert_equal Time.at(0), person.birthday

    assert_raises NoMethodError do
      person.age
    end

    refute person.respond_to?(:missing)
    refute person.respond_to?(:firstName)
    refute person.respond_to?(:lastName)
  end
end
