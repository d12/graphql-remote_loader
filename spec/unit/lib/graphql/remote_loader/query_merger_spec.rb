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

      context "when there are field aliases" do
        let(:result) { subject.merge([["foo: bar", 2]]) }

        it "returns the expected query" do
          expected_result = <<~GRAPHQL
            query {
              p2foo: bar
            }
          GRAPHQL
          expect(result).to eq(expected_result.strip)
        end
      end

      context "when there are directives" do
        let(:result) { subject.merge([["foo @bar", 2]]) }

        it "returns the expected query" do
          expected_result = <<~GRAPHQL
            query {
              p2foo: foo @bar
            }
          GRAPHQL
          expect(result).to eq(expected_result.strip)
        end
      end

      context "when there are defined fragments" do
        let(:result) { subject.merge([["query { foo { ... MyFragment } } fragment MyFragment on Foo { bar }", 2]]) }

        # In order to resolve fields on fragments correctly, all
        # fields on fragments must have prefixes
        it "returns the expected query" do
          expected_result = <<~GRAPHQL
            query {
              p2foo: foo {
                ...MyFragment
              }
            }

            fragment MyFragment on Foo {
              p2bar: bar
            }
          GRAPHQL
          expect(result).to eq(expected_result.strip)
        end
      end

      context "when there are directives with arguments" do
        let(:result) { subject.merge([["foo @bar(buzz: 1)", 2]]) }

        it "returns the expected query" do
          expected_result = <<~GRAPHQL
            query {
              p2foo: foo @bar(buzz: 1)
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

      context "when there are inline fragments" do
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

      context "when there are aliases" do
        context "when there is no overlap" do
          let(:result) { subject.merge([["foo: bar", 2], ["buzz: bazz", 3]]) }

          it "returns the expected query" do
            expected_result = <<~GRAPHQL
              query {
                p3buzz: bazz
                p2foo: bar
              }
            GRAPHQL
            expect(result).to eq(expected_result.strip)
          end
        end

        # Notice we do not merge if aliases are differing.
        context "when there is field name overlap but differing aliases" do
          let(:result) { subject.merge([["foo: bar", 2], ["buzz: bar", 3]]) }

          it "returns the expected query" do
            expected_result = <<~GRAPHQL
              query {
                p3buzz: bar
                p2foo: bar
              }
            GRAPHQL
            expect(result).to eq(expected_result.strip)
          end
        end

        context "when there is field name overlap and same aliases" do
          let(:result) { subject.merge([["foo: bar", 2], ["foo: bar", 3]]) }

          it "returns the expected query" do
            expected_result = <<~GRAPHQL
              query {
                p6foo: bar
              }
            GRAPHQL
            expect(result).to eq(expected_result.strip)
          end
        end
      end

      context "when there are directives" do
        let(:result) { subject.merge([["foo @bar", 2], ["buzz @bazz", 3]]) }

        it "returns the expected query" do
          expected_result = <<~GRAPHQL
            query {
              p3buzz: buzz @bazz
              p2foo: foo @bar
            }
          GRAPHQL
          expect(result).to eq(expected_result.strip)
        end
      end

      context "when there are directives with arguments" do
        let(:result) { subject.merge([["foo @bar(a: 1)", 2], ["buzz @bazz(a: 1)", 3]]) }

        it "returns the expected query" do
          expected_result = <<~GRAPHQL
            query {
              p3buzz: buzz @bazz(a: 1)
              p2foo: foo @bar(a: 1)
            }
          GRAPHQL
          expect(result).to eq(expected_result.strip)
        end
      end

      context "when there are defined fragments that are unique" do
        let(:result) { subject.merge([
            ["query { foo { ... MyFragment } } fragment MyFragment on Foo { bar }", 2],
            ["query { foo { ... OtherFragment } } fragment OtherFragment on Buzz { bazz }", 3]
          ])}

        # In order to resolve fields on fragments correctly, all
        # fields on fragments must have prefixes
        it "returns the expected query" do
          expected_result = <<~GRAPHQL
            query {
              p6foo: foo {
                ...OtherFragment
                ...MyFragment
              }
            }

            fragment OtherFragment on Buzz {
              p3bazz: bazz
            }

            fragment MyFragment on Foo {
              p2bar: bar
            }
          GRAPHQL
          expect(result).to eq(expected_result.strip)
        end
      end

      context "when there are defined fragments that are NOT unique" do
        let(:result) { subject.merge([
            ["query { foo { ... MyFragment } } fragment MyFragment on Foo { bar }", 2],
            ["query { foo { ... MyFragment } } fragment MyFragment on Foo { bar bazz }", 3]
          ])}

        # In order to resolve fields on fragments correctly, all
        # fields on fragments must have prefixes
        it "returns the expected query" do
          expected_result = <<~GRAPHQL
            query {
              p6foo: foo {
                ...MyFragment
              }
            }

            fragment MyFragment on Foo {
              p6bar: bar
              p3bazz: bazz
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

      context "when there are merging inline fragments" do
        let(:result) { subject.merge[["foo { ... on Bar { buzz } }", 2], ["foo { ... on Bar { bazz } }", 3]] }

        # It may seem strange that the inline fragments don't get merged here since their types are equal.
        # And I agree. That's certainly odd.
        # But, it works and is 100% valid, and there other things I'd like to tackle first!
        # TODO: Merge inline fragment selections iff the spread type is the same
        it "returns the expected query" do
          expected_result = <<~GRAPHQL
            query {
              p6foo {
                ... on Bar {
                  p3bazz
                }
                ... on Bar {
                  p2buzz
                }
              }
            }
          GRAPHQL
        end
      end
    end
  end
end
