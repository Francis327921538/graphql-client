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
    assert_equal QueryType, Types::Query.type
    assert_equal "TestSchemaType::Types::Query", Types::Query.inspect
  end

  def test_person_object_class
    assert Types::Person < Types::Node
    assert_equal PersonType, Types::Person.type
    assert_equal "TestSchemaType::Types::Person", Types::Person.inspect
  end

  def test_id_scalar_object
    assert_equal GraphQL::ID_TYPE, Types::ID.type
    assert_equal "TestSchemaType::Types::ID", Types::ID.inspect
  end

  def test_string_scalar_object
    assert_equal GraphQL::STRING_TYPE, Types::String.type
    assert_equal "TestSchemaType::Types::String", Types::String.inspect
  end

  def test_int_scalar_object
    assert_equal GraphQL::INT_TYPE, Types::Int.type
    assert_equal "TestSchemaType::Types::Int", Types::Int.inspect
  end

  def test_datetime_scalar_object
    assert_equal DateTime, Types::DateTime.type
    assert_equal "TestSchemaType::Types::DateTime", Types::DateTime.inspect
    assert_equal Time.at(0), Types::DateTime.cast(Time.at(0).iso8601)
  end

  def test_boolean_scalar_object
    assert_equal GraphQL::BOOLEAN_TYPE, Types::Boolean.type
    assert_equal "TestSchemaType::Types::Boolean", Types::Boolean.inspect
  end

  def test_node_interface_module
    assert_equal NodeType, Types::Node.type
    assert_equal "TestSchemaType::Types::Node", Types::Node.inspect
  end

  def test_search_result_union
    assert_kind_of GraphQL::Client::SchemaClass::UnionType, Types::SearchResult
    assert_equal SearchResultUnion, Types::SearchResult.type
    assert_equal "TestSchemaType::Types::SearchResult", Types::SearchResult.inspect
  end

  def test_plan_enum_constants
    assert_kind_of GraphQL::Client::SchemaClass::EnumType, Types::Plan
    assert_equal PlanEnum, Types::Plan.type
    assert_equal "TestSchemaType::Types::Plan", Types::Plan.inspect
    assert_equal "FREE", Types::Plan.cast("FREE")

    assert_equal "FREE", Types::Plan::FREE
    assert_equal "SMALL", Types::Plan::SMALL
    assert_equal "LARGE", Types::Plan::LARGE
  end

  def test_person_fields
    assert_kind_of GraphQL::Client::SchemaClass::NonNullType, Types::Person.fields[:name]
    assert_equal Types::String, Types::Person.fields[:name].of_klass
    assert_equal "TestSchemaType::Types::String!", Types::Person.fields[:name].inspect

    assert_kind_of GraphQL::Client::SchemaClass::NonNullType, Types::Person.fields[:friends]
    assert_kind_of GraphQL::Client::SchemaClass::ListType, Types::Person.fields[:friends].of_klass
    assert_kind_of GraphQL::Client::SchemaClass::NonNullType, Types::Person.fields[:friends].of_klass.of_klass
    assert_kind_of GraphQL::Client::SchemaClass::ObjectType, Types::Person.fields[:friends].of_klass.of_klass.of_klass
    assert_equal Types::Person, Types::Person.fields[:friends].of_klass.of_klass.of_klass
    assert_equal "[TestSchemaType::Types::Person!]!", Types::Person.fields[:friends].inspect

    assert_kind_of GraphQL::Client::SchemaClass::NonNullType, Types::Person.fields[:id]
    assert_equal Types::ID, Types::Person.fields[:id].of_klass
    assert_equal "TestSchemaType::Types::ID!", Types::Person.fields[:id].inspect
  end

  def test_query_object_subclass
    query_klass = Class.new do
      include Types::Query
    end
    person_klass = Class.new do
      include Types::Person
    end

    assert_equal QueryType, query_klass.type
    assert_equal PersonType, person_klass.type

    query_klass.define_field :me, person_klass
    assert_includes query_klass.instance_methods, :me

    person_klass.define_field :id, Types::Person.fields[:id]
    assert_includes person_klass.instance_methods, :id

    assert query = query_klass.new({
      "me" => {
        "id" => "1"
      }
    })

    assert_kind_of Types::Person, query.me
    assert_kind_of person_klass, query.me
    assert_equal "1", query.me.id

    assert_equal "#<TestSchemaType::Types::Query me=...>", query.inspect

    assert_raises NoMethodError do
      query.todo
    end
  end

  def test_person_object_subclass
    friend_klass = Class.new do
      include Types::Person
    end
    friend_klass.define_field :id, Types::Person.fields[:id]
    friend_klass.define_field :name, Types::Person.fields[:name]

    person_klass = Class.new do
      include Types::Person
    end

    person_klass.define_field :id, Types::Person.fields[:id]
    person_klass.define_field :name, Types::Person.fields[:name]
    person_klass.define_field :firstName, Types::Person.fields[:firstName]
    person_klass.define_field :lastName, Types::Person.fields[:lastName]
    person_klass.define_field :birthday, Types::Person.fields[:birthday]
    person_klass.define_field :plan, Types::Person.fields[:plan]
    person_klass.define_field :friends, GraphQL::Client::SchemaClass::NonNullType.new(
      GraphQL::Client::SchemaClass::ListType.new(
        GraphQL::Client::SchemaClass::NonNullType.new(
          friend_klass)))

    assert_includes person_klass.instance_methods, :id
    assert_includes person_klass.instance_methods, :name
    assert_includes person_klass.instance_methods, :first_name
    assert_includes person_klass.instance_methods, :last_name
    assert_includes person_klass.instance_methods, :lastName
    assert_includes person_klass.instance_methods, :plan

    assert person = person_klass.new({
      "id" => "1",
      "name" => "Josh",
      "firstName" => "Joshua",
      "lastName" => "Peek",
      "birthday" => Time.at(0).iso8601,
      "plan" => "FREE",
      "friends" => [{
        "id" => "2",
        "name" => "David"
      }]
    })

    assert_kind_of person_klass, person
    assert_kind_of Types::Person, person
    assert_kind_of Types::Node, person

    refute person.errors.any?

    assert_equal "1", person.id
    assert_equal "Josh", person.name
    assert_equal true, person.name?
    assert_equal "Joshua", person.first_name
    assert_equal "Peek", person.last_name
    assert_equal Time.at(0), person.birthday
    assert_equal Types::Plan::FREE, person.plan
    assert_equal 1, person.friends.length
    assert_equal "2", person.friends[0].id
    assert_equal "David", person.friends[0].name

    assert_equal({
      "id" => "1",
      "name" => "Josh",
      "firstName" => "Joshua",
      "lastName" => "Peek",
      "birthday" => Time.at(0).iso8601,
      "plan" => "FREE",
      "friends" => [{
        "id" => "2",
        "name" => "David"
      }]
    }, person.to_h)

    assert_equal "#<TestSchemaType::Types::Person id=\"1\" name=\"Josh\" firstName=\"Joshua\" lastName=\"Peek\" birthday=\"1969-12-31T16:00:00-08:00\" plan=\"FREE\" friends=...>", person.inspect

    assert_raises NoMethodError do
      person.age
    end

    refute person.respond_to?(:missing)

    GraphQL::Client::Deprecation.silence do
      assert_equal "Person", person.typename
    end

    GraphQL::Client::Deprecation.silence do
      assert person.type_of?(:Person)
      assert person.type_of?(:Node)
      refute person.type_of?(:Photo)
    end

    GraphQL::Client::Deprecation.silence do
      assert_equal "Joshua", person.firstName
    end
  end

  def test_interface_cast
    query_klass = Class.new do
      include Types::Query
    end
    person_klass = Class.new do
      include Types::Person
    end
    node_klass = GraphQL::Client::SchemaClass::PossibleTypes.new({"Person" => person_klass})

    query_klass.define_field :node, node_klass
    assert_includes query_klass.instance_methods, :node

    person_klass.define_field :id, Types::Person.fields[:id]
    assert_includes person_klass.instance_methods, :id

    assert query = query_klass.new({
      "node" => {
        "__typename" => "Person",
        "id" => "1"
      }
    })

    assert_kind_of Types::Node, query.node
    assert_kind_of Types::Person, query.node
    assert_kind_of person_klass, query.node
    assert_equal "1", query.node.id
  end

  def test_union_cast
    query_klass = Class.new do
      include Types::Query
    end
    person_klass = Class.new do
      include Types::Person
    end
    search_result_klass = GraphQL::Client::SchemaClass::PossibleTypes.new({"Person" => person_klass})

    query_klass.define_field :firstSearchResult, search_result_klass
    assert_includes query_klass.instance_methods, :first_search_result

    person_klass.define_field :id, Types::Person.fields[:id]
    assert_includes person_klass.instance_methods, :id

    assert query = query_klass.new({
      "firstSearchResult" => {
        "__typename" => "Person",
        "id" => "1"
      }
    })

    assert_kind_of Types::Person, query.first_search_result
    assert_kind_of person_klass, query.first_search_result
    assert_equal "1", query.first_search_result.id
  end
end
