require "spec_helper"

describe GraphQL::RemoteLoader::QueryMerger do
  subject { described_class }
  describe ".merge" do
    context "when passed one query" do
      context "when there is one field" do
        let(:result) { subject.merge([["foo", 2]]) }

        it "returns the expected query" do
          expected_result = <<~GRAPHQL
            query {
              p2foo: foo
            }
          GRAPHQL
          expect(result).to eq(expected_result.strip)
        end
      end

      context "when there is multiple fields" do
        let(:result) { subject.merge([["foo bar { buzz }", 2]]) }

        it "returns the expected query" do
          expected_result = <<~GRAPHQL
            query {
              p2foo: foo
              p2bar: bar {
                p2buzz: buzz
              }
            }
          GRAPHQL
          expect(result).to eq(expected_result.strip)
        end
      end

      context "when there are arguments" do
        let(:result) { subject.merge([["foo(bar: 5){ buzz }", 2]]) }

        it "returns the expected query" do
          expected_result = <<~GRAPHQL
            query {
              p2foo: foo(bar: 5) {
                p2buzz: buzz
              }
            }
          GRAPHQL
          expect(result).to eq(expected_result.strip)
        end
      end

      context "when there are fragment spreads" do
        let(:result) { subject.merge([["foo { ... on Bar { buzz } }", 2]]) }

        it "returns the expected query" do
          expected_result = <<~GRAPHQL
            query {
              p2foo: foo {
                ... on Bar {
                  p2buzz: buzz
                }
              }
            }
          GRAPHQL
          expect(result).to eq(expected_result.strip)
        end
      end
    end

    context "when passed multiple queries" do
      context "when there is no overlap" do
        let(:result) { subject.merge([["foo bar", 2], ["buzz bazz", 3]]) }

        it "returns the expected query" do
          expected_result = <<~GRAPHQL
            query {
              p3buzz: buzz
              p3bazz: bazz
              p2foo: foo
              p2bar: bar
            }
          GRAPHQL
          expect(result).to eq(expected_result.strip)
        end
      end

      context "when there is no overlap because of arguments" do
        let(:result) { subject.merge([["foo(buzz: 1) { bar }", 2], ["foo(buzz: 2) {  bar }", 3]]) }

        it "returns the expected query" do
          expected_result = <<~GRAPHQL
            query {
              p3foo: foo(buzz: 2) {
                p3bar: bar
              }
              p2foo: foo(buzz: 1) {
                p2bar: bar
              }
            }
          GRAPHQL
          expect(result).to eq(expected_result.strip)
        end
      end

      context "when there is overlap" do
        let(:result) { subject.merge([["foo { bar }", 2], ["foo { buzz }", 3]]) }

        it "returns the expected query" do
          expected_result = <<~GRAPHQL
            query {
              p6foo: foo {
                p3buzz: buzz
                p2bar: bar
              }
            }
          GRAPHQL
          expect(result).to eq(expected_result.strip)
        end
      end

      context "when there is argument overlap" do
        let(:result) { subject.merge([["foo(buzz: 1) { bar }", 2], ["foo(buzz: 1) {  bar bazz }", 3]]) }

        it "returns the expected query" do
          expected_result = <<~GRAPHQL
            query {
              p6foo: foo(buzz: 1) {
                p6bar: bar
                p3bazz: bazz
              }
            }
          GRAPHQL
          expect(result).to eq(expected_result.strip)
        end
      end
    end
  end
end
