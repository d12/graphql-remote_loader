require "spec_helper"
require 'byebug'

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
      TestLoader.any_instance.stub(:query).and_return({"p2test" => "test_result"})
      TestLoader.any_instance.should_receive(:query).once

      results = GraphQL::Batch.batch do
        TestLoader.load("test")
      end

      expect(results["test"]).to eq("test_result")
    end
  end

  context "hitting the loader multiple times for one field" do
    it "returns the correct results and only makes one query" do
      TestLoader.any_instance.stub(:query).and_return({"p6test" => "test_result"})
      TestLoader.any_instance.should_receive(:query).once

      first, second = GraphQL::Batch.batch do
        Promise.all([TestLoader.load("test"), TestLoader.load("test")])
      end

      expect(first["test"]).to eq("test_result")
      expect(second["test"]).to eq("test_result")
    end
  end

  context "hitting the loader with multiple fields" do
    it "returns the correct results and only makes one query" do
      TestLoader.any_instance.stub(:query).and_return({
        "p2foo" => "foo_result",
        "p3bar" => "bar_result"
      })
      TestLoader.any_instance.should_receive(:query).once

      first, second = GraphQL::Batch.batch do
        Promise.all([TestLoader.load("foo"), TestLoader.load("bar")])
      end

      expect(first["foo"]).to eq("foo_result")
      expect(second["bar"]).to eq("bar_result")
    end

    it "fulfills promises with no un-requested data" do
      TestLoader.any_instance.stub(:query).and_return({
        "p2foo" => "foo_result",
        "p3bar" => "bar_result"
      })
      TestLoader.any_instance.should_receive(:query).once

      first, second = GraphQL::Batch.batch do
        Promise.all([TestLoader.load("foo { bar }"), TestLoader.load("foo { buzz }")])
      end

      expect(first["bar"]).to be_nil
      expect(second["foo"]).to be_nil
    end
  end

  context "hitting the loader with an array" do
    it "returns the correct results and only makes one query" do
      TestLoader.any_instance.stub(:query).and_return({
        "p2foo" => [{"p2bar" => 5}, {"p2bar" => 6}]
      })
      TestLoader.any_instance.should_receive(:query).once

      result = GraphQL::Batch.batch do
        TestLoader.load("foo { bar }")
      end

      expect(result["foo"][0]["bar"]).to eq(5)
      expect(result["foo"][1]["bar"]).to eq(6)
    end
  end

  context "hitting the loader with overlapping fields with different sub-selections" do
    it "returns the correct results and only makes one query" do
      TestLoader.any_instance.stub(:query).and_return({
        "p6foo" => {
          "p2bar" => "bar_result",
          "p3buzz" => "buzz_result"
        }
      })
      TestLoader.any_instance.should_receive(:query).once

      first, second = GraphQL::Batch.batch do
        Promise.all([TestLoader.load("foo { bar }"), TestLoader.load("foo { buzz }")])
      end

      expect(first["foo"]["bar"]).to eq("bar_result")
      expect(second["foo"]["buzz"]).to eq("buzz_result")
    end

    it "fulfills promises with no un-requested data" do
      TestLoader.any_instance.stub(:query).and_return({
        "p6foo" => {
          "p2bar" => "bar_result",
          "p3buzz" => "buzz_result"
        }
      })
      TestLoader.any_instance.should_receive(:query).once

      first, second = GraphQL::Batch.batch do
        Promise.all([TestLoader.load("foo { bar }"), TestLoader.load("foo { buzz }")])
      end

      # These are both nil because the first request asked for foo,buzz and the second
      # asked for foo,bar. foo,buzz should not be exposed in the first result,
      # and foo,bar should not be exposed in the second result.
      expect(first["foo"]["buzz"]).to be_nil
      expect(second["foo"]["bar"]).to be_nil
    end
  end

  context "hitting the loader with fields with differing argument values" do
    it "returns the correct results and only makes one query" do
      TestLoader.any_instance.stub(:query).and_return({
        "p2foo" => {
          "p2buzz" => "buzz_first_result"
        },
        "p3foo" => {
          "p3buzz" => "buzz_second_result"
        }
      })
      TestLoader.any_instance.should_receive(:query).once

      first, second = GraphQL::Batch.batch do
        Promise.all([TestLoader.load("foo(bar: 1) { buzz }"), TestLoader.load("foo(bar: 2){ buzz }")])
      end

      expect(first["foo"]["buzz"]).to eq("buzz_first_result")
      expect(second["foo"]["buzz"]).to eq("buzz_second_result")
    end
  end

  context "hitting the loader with one field with an alias" do
    it "returns the correct results and only makes one query" do
      TestLoader.any_instance.stub(:query).and_return({
        "p2p3foobar" => "bar_result"
      })
      TestLoader.any_instance.should_receive(:query).once

      result = GraphQL::Batch.batch do
        TestLoader.load("foo: bar")
      end

      expect(result["foo"]).to eq("bar_result")
    end
  end

  context "hitting the loader with fields with overlapping aliases" do
    it "returns the correct results and only makes one query" do
      TestLoader.any_instance.stub(:query).and_return({
        "p2p3foobar" => "bar_result",
        "p3p4buzzbazz" => "bazz_result"
      })
      TestLoader.any_instance.should_receive(:query).once

      first, second = GraphQL::Batch.batch do
        Promise.all([TestLoader.load("foo: bar"), TestLoader.load("buzz: bazz")])
      end

      expect(first["foo"]).to eq("bar_result")
      expect(second["buzz"]).to eq("bazz_result")
    end

    it "fulfills promises with only the data they asked for" do
      TestLoader.any_instance.stub(:query).and_return({
        "p2p3foobar" => "bar_result",
        "p3p4buzzbazz" => "bazz_result"
      })
      TestLoader.any_instance.should_receive(:query).once

      first, second = GraphQL::Batch.batch do
        Promise.all([TestLoader.load("foo: bar"), TestLoader.load("buzz: bazz")])
      end

      expect(second["foo"]).to be_nil
      expect(first["buzz"]).to be_nil
    end
  end
end
