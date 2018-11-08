require "spec_helper"

class TestLoader < GraphQL::RemoteLoader::Loader
  def query(query_string)
  end
end

describe GraphQL::RemoteLoader::Loader do
  subject { described_class }

  before do
    TestLoader.reset_index
  end

  context "hitting the loader once" do
    it "returns the correct results and only makes one query" do
      TestLoader.any_instance.should_receive(:query).once
        .with("query { p2test: test }", anything)
        .and_return({"data" => {"p2test" => "test_result"}})

      results = GraphQL::Batch.batch do
        TestLoader.load("test")
      end

      expect(results["data"]["test"]).to eq("test_result")
    end
  end

  context "hitting the loader multiple times for one field" do
    it "returns the correct results and only makes one query" do
      TestLoader.any_instance.should_receive(:query).once
        .with("query { p6test: test }", anything)
        .and_return({"data" => {"p6test" => "test_result"}})

      first, second = GraphQL::Batch.batch do
        Promise.all([TestLoader.load("test"), TestLoader.load("test")])
      end

      expect(first["data"]["test"]).to eq("test_result")
      expect(second["data"]["test"]).to eq("test_result")
    end
  end

  context "hitting the loader with multiple fields" do
    it "returns the correct results and only makes one query" do
      TestLoader.any_instance.should_receive(:query).once
        .with("query { p3bar: bar p2foo: foo }", anything)
        .and_return({
          "data" => {
            "p2foo" => "foo_result",
            "p3bar" => "bar_result"
          }
        })

      first, second = GraphQL::Batch.batch do
        Promise.all([TestLoader.load("foo"), TestLoader.load("bar")])
      end

      expect(first["data"]["foo"]).to eq("foo_result")
      expect(second["data"]["bar"]).to eq("bar_result")

      # un-requested data should not be present
      expect(first["data"]["bar"]).to be_nil
      expect(second["data"]["foo"]).to be_nil
    end
  end

  context "when variables are provided" do
    it "interpolates integer variables correctly" do
      TestLoader.any_instance.should_receive(:query).once
        .with("query { p2foo: foo(bar: 5) }", anything)
        .and_return({
          "data" => {
            "p2foo" => "foo_result"
          }
        })

      results = GraphQL::Batch.batch do
        TestLoader.load("foo(bar: $my_variable)", variables: { my_variable: 5 })
      end

      expect(results["data"]["foo"]).to eq("foo_result")
    end

    it "interpolates float variables correctly" do
      TestLoader.any_instance.should_receive(:query).once
        .with("query { p2foo: foo(bar: 5.545) }", anything)
        .and_return({
          "data" => {
            "p2foo" => "foo_result"
          }
        })

      results = GraphQL::Batch.batch do
        TestLoader.load("foo(bar: $my_variable)", variables: { my_variable: 5.545 })
      end

      expect(results["data"]["foo"]).to eq("foo_result")
    end

    it "interpolates boolean variables correctly" do
      TestLoader.any_instance.should_receive(:query).once
        .with("query { p2foo: foo(bar: true) }", anything)
        .and_return({
          "data" => {
            "p2foo" => "foo_result"
          }
        })

      results = GraphQL::Batch.batch do
        TestLoader.load("foo(bar: $my_variable)", variables: { my_variable: true })
      end

      expect(results["data"]["foo"]).to eq("foo_result")
    end

    it "interpolates string variables correctly" do
      TestLoader.any_instance.should_receive(:query).once
        .with("query { p2foo: foo(bar: \"testing string\") }", anything)
        .and_return({
          "data" => {
            "p2foo" => "foo_result"
          }
        })

      results = GraphQL::Batch.batch do
        TestLoader.load("foo(bar: $my_variable)", variables: { my_variable: "testing string" })
      end

      expect(results["data"]["foo"]).to eq("foo_result")
    end


    # The string we're inserting here is:
    # "\"
    # (the quotes are part of the string)
    it "interpolates difficult string variables correctly" do
      expected_query_string = <<~HEREDOC.strip
        query { p2foo: foo(bar: \"\\\"\\\\\\\"\") }
      HEREDOC

      TestLoader.any_instance.should_receive(:query).once
        .with(expected_query_string, anything)
        .and_return({
          "data" => {
            "p2foo" => "foo_result"
          }
        })

      results = GraphQL::Batch.batch do
        TestLoader.load("foo(bar: $my_variable)", variables: { my_variable: "\"\\\"" })
      end

      expect(results["data"]["foo"]).to eq("foo_result")
    end

    it "interpolates other variables correctly" do
      TestLoader.any_instance.should_receive(:query).once
        .with("query { p2foo: foo(bar: \"Object\") }", anything)
        .and_return({
          "data" => {
            "p2foo" => "foo_result"
          }
        })

      results = GraphQL::Batch.batch do
        TestLoader.load("foo(bar: $my_variable)", variables: { my_variable: Object })
      end

      expect(results["data"]["foo"]).to eq("foo_result")
    end
  end

  context "hitting the loader with an array" do
    it "returns the correct results and only makes one query" do
      TestLoader.any_instance.should_receive(:query).once
        .with("query { p2foo: foo { p2bar: bar } }", anything)
        .and_return({
          "data" => {
            "p2foo" => [{"p2bar" => 5}, {"p2bar" => 6}]
          }
        })

      result = GraphQL::Batch.batch do
        TestLoader.load("foo { bar }")
      end

      expect(result["data"]["foo"][0]["bar"]).to eq(5)
      expect(result["data"]["foo"][1]["bar"]).to eq(6)
    end
  end

  context "hitting the loader with overlapping fields with different sub-selections" do
    it "returns the correct results and only makes one query" do
      TestLoader.any_instance.should_receive(:query).once
        .with("query { p6foo: foo { p3buzz: buzz p2bar: bar } }", anything)
        .and_return({
          "data" => {
            "p6foo" => {
              "p2bar" => "bar_result",
              "p3buzz" => "buzz_result"
            }
          }
        })

      first, second = GraphQL::Batch.batch do
        Promise.all([TestLoader.load("foo { bar }"), TestLoader.load("foo { buzz }")])
      end

      expect(first["data"]["foo"]["bar"]).to eq("bar_result")
      expect(second["data"]["foo"]["buzz"]).to eq("buzz_result")

      # These are both nil because the first request asked for foo,buzz and the second
      # asked for foo,bar. foo,buzz should not be exposed in the first result,
      # and foo,bar should not be exposed in the second result.
      expect(first["data"]["foo"]["buzz"]).to be_nil
      expect(second["data"]["foo"]["bar"]).to be_nil
    end
  end

  context "hitting the loader with fields with differing argument values" do
    it "returns the correct results and only makes one query" do
      TestLoader.any_instance.should_receive(:query).once
        .with("query { p3foo: foo(bar: 2) { p3buzz: buzz } p2foo: foo(bar: 1) { p2buzz: buzz } }", anything)
        .and_return({
          "data" => {
            "p2foo" => {
              "p2buzz" => "buzz_first_result"
            },
            "p3foo" => {
              "p3buzz" => "buzz_second_result"
            }
          }
        })

      first, second = GraphQL::Batch.batch do
        Promise.all([TestLoader.load("foo(bar: 1) { buzz }"), TestLoader.load("foo(bar: 2){ buzz }")])
      end

      expect(first["data"]["foo"]["buzz"]).to eq("buzz_first_result")
      expect(second["data"]["foo"]["buzz"]).to eq("buzz_second_result")
    end
  end

  context "hitting the loader with one field with an alias" do
    it "returns the correct results and only makes one query" do
      TestLoader.any_instance.should_receive(:query).once
        .with("query { p2foo: bar }", anything)
        .and_return({
          "data" => {
            "p2foo" => "bar_result"
          }
        })

      result = GraphQL::Batch.batch do
        TestLoader.load("foo: bar")
      end

      expect(result["data"]["foo"]).to eq("bar_result")
    end
  end

  context "hitting the loader with fields with overlapping aliases" do
    it "returns the correct results and only makes one query" do
      TestLoader.any_instance.should_receive(:query).once
        .with("query { p3foo: bazz p2foo: bar }", anything)
        .and_return({
          "data" => {
            "p2foo" => "bar_result",
            "p3foo" => "bazz_result"
          }
        })

      first, second = GraphQL::Batch.batch do
        Promise.all([TestLoader.load("foo: bar"), TestLoader.load("foo: bazz")])
      end

      expect(first["data"]["foo"]).to eq("bar_result")
      expect(second["data"]["foo"]).to eq("bazz_result")
    end

    it "fulfills promises with only the data they asked for" do
      TestLoader.any_instance.should_receive(:query).once
        .with("query { p3buzz: bazz p2foo: bar }", anything)
        .and_return({
          "data" => {
            "p2foo" => "bar_result",
            "p3buzz" => "bazz_result"
          }
        })

      first, second = GraphQL::Batch.batch do
        Promise.all([TestLoader.load("foo: bar"), TestLoader.load("buzz: bazz")])
      end

      expect(second["data"]["foo"]).to be_nil
      expect(first["data"]["buzz"]).to be_nil
    end
  end

  context "when errors are returned" do
    context "when errored field is asked for once" do
      it "fulfills promise with error map if it requested the field that errored" do
        TestLoader.any_instance.should_receive(:query).once
          .with("query { p2foo: foo }", anything)
          .and_return({
            "data" => {
              "p2foo" => nil
            },
            "errors" => [{
              "message" => "Something went wrong!",
              "path" => ["p2foo"]
            }]
          })

        result = GraphQL::Batch.batch do
          TestLoader.load("foo")
        end

        expect(result["data"]["foo"]).to be_nil
        expect(result["errors"][0]["message"]).to eq("Something went wrong!")
        expect(result["errors"][0]["path"]).to eq(["foo"])
      end
    end

    context "when data key isn't present" do
      it "fulfills promise with error map if it requested the field that errored" do
        TestLoader.any_instance.should_receive(:query).once
          .with("query { p2foo: foo }", anything)
          .and_return({
            "errors" => [{
              "message" => "Something went wrong!",
              "path" => ["p2foo"]
            }]
          })

        result = GraphQL::Batch.batch do
          TestLoader.load("foo")
        end

        expect(result["data"]).to be_nil
        expect(result["errors"][0]["message"]).to eq("Something went wrong!")
        expect(result["errors"][0]["path"]).to eq(["foo"])
      end
    end

    context "when errored field is asked for multiple times" do
      it "fulfills promise with error map if it requested the field that errored" do
        TestLoader.any_instance.should_receive(:query).once
          .with("query { p6foo: foo }", anything)
          .and_return({
            "data" => {
              "p6foo" => nil
            },
            "errors" => [{
              "message" => "Something went wrong!",
              "path" => ["p6foo"]
            }]
          })

        results = GraphQL::Batch.batch do
          Promise.all([TestLoader.load("foo"), TestLoader.load("foo")])
        end

        results.each do |result|
          expect(result["data"]["foo"]).to be_nil
          expect(result["errors"][0]["message"]).to eq("Something went wrong!")
          expect(result["errors"][0]["path"]).to eq(["foo"])
        end
      end
    end
  end

  context "#load_on_relay_node" do
    it "returns value" do
      TestLoader.any_instance.should_receive(:query).once
        .with("query { p2node: node(id: \"id\") { ... on Type { p2viewer: viewer } } }", anything)
        .and_return({
          "data" => {
            "p2node" => {
              "p2viewer" => "foo"
            }
          }
        })

      result = GraphQL::Batch.batch do
        TestLoader.load_on_relay_node("id", "Type", "viewer")
      end

      expect(result["data"]["node"]["viewer"]).to eq("foo")
    end
  end

  context "#load_value" do
    context "when no errors" do
      it "returns value" do
        TestLoader.any_instance.should_receive(:query).once
          .with("query { p2foo: foo { p2bar: bar } }", anything)
          .and_return({
            "data" => {
              "p2foo" => {
                "p2bar" => 5
              }
            }
          })

        result = GraphQL::Batch.batch do
          TestLoader.load_value("foo", "bar")
        end

        expect(result).to eq(5)
      end
    end

    context "when there are errors" do
      it "returns nil" do
        TestLoader.any_instance.should_receive(:query).once
          .with("query { p2foo: foo { p2bar: bar } }", anything)
          .and_return({
            "data" => {
              "p2foo" => nil
            },
            "errors" => [{
              "message" => "Something went wrong!",
              "path" => ["p2foo", "p2bar"]
            }]
          })

        result = GraphQL::Batch.batch do
          TestLoader.load_value("foo", "bar")
        end

        # load_value does not pass along errors. Perhaps it should raise in future versions?
        expect(result).to be_nil
      end
    end
  end
end
