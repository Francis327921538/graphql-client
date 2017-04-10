# frozen_string_literal: true
require "graphql"
require "graphql/client/schema_class"
require "minitest/autorun"
require "time"

class TestSchemaType < MiniTest::Test
  DateTime = GraphQL::ScalarType.define do
    name "DateTime"
    coerce_input ->(value) do
      Time.iso8601(value)
    end
    coerce_result ->(value) do
      value.utc.iso8601
    end
  end

  NodeType = GraphQL::InterfaceType.define do
    name "Node"
    field :id, !types.ID
  end

  PersonType = GraphQL::ObjectType.define do
    name "Person"
    interfaces [NodeType]
    field :name, !types.String
    field :firstName, !types.String
    field :lastName, !types.String
    field :age, !types.Int
    field :birthday, !DateTime
  end

  QueryType = GraphQL::ObjectType.define do
    name "Query"
    field :me, !PersonType
  end

  Schema = GraphQL::Schema.define(query: QueryType) do
    resolve_type ->(_obj, _ctx) { raise NotImplementedError }
  end

  Types = GraphQL::Client::SchemaClass.generate(Schema)

  def test_query_object_class
    assert_equal Class, Types::Query.class
    assert_includes Types::Query.instance_methods, :me

    assert query = Types::Query.new({
      "me" => {
        "id" => "1"
      }
    })

    assert_kind_of Types::Person, query.me
    assert_equal "1", query.me.id
  end

  def test_person_object_class
    assert_equal Class, Types::Person.class
    assert Types::Person < Types::Node
    assert_includes Types::Person.instance_methods, :id
    assert_includes Types::Person.instance_methods, :name
    assert_includes Types::Person.instance_methods, :first_name
    assert_includes Types::Person.instance_methods, :last_name
    refute_includes Types::Person.instance_methods, :lastName

    assert person = Types::Person.new({
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

    assert_raises GraphQL::Client::SchemaClass::UnfetchedFieldError do
      person.age
    end

    refute person.respond_to?(:missing)
    refute person.respond_to?(:firstName)
    refute person.respond_to?(:lastName)
  end

  def test_id_scalar_object
    skip
  end

  def test_string_scalar_object
    skip
  end

  def test_int_scalar_object
    skip
  end

  def test_datetime_scalar_object
    skip
  end

  def test_node_interface_module
    assert_equal Module, Types::Node.class
    assert_includes Types::Node.instance_methods, :id
  end

  def test_boolean_scalar_object
    skip
  end
end
