module GraphQL
  module RemoteLoader
    # Given a list of queries and their prime UIDs, generate the merged and labeled
    # GraphQL query to be sent off to the remote backend.
    class QueryMerger
      class << self
        def merge(queries_and_primes)
          parsed_queries = queries_and_primes.map do |query, prime|
            parsed_query = parse(query)
            attach_primes!(parsed_query.definitions[0].children, prime)

            parsed_query
          end

          merge_parsed_queries(parsed_queries).to_query_string
        end

        private

        def merge_parsed_queries(parsed_queries)
          merged_query = parsed_queries.pop

          parsed_queries.each do |query|
            merge_query_recursive(query.definitions[0], merged_query.definitions[0])
          end

          apply_aliases!(merged_query.definitions[0].selections)
          merged_query
        end

        # merges a_query into b_query
        def merge_query_recursive(a_query, b_query)
          a_query.selections.each do |a_query_selection|
            matching_field = b_query.selections.find do |b_query_selection|
              a_query_selection.name == b_query_selection.name &&
                arguments_equal?(a_query_selection.arguments, b_query_selection.arguments)
            end

            if matching_field
              new_prime = matching_field.instance_variable_get(:@prime) *
                a_query_selection.instance_variable_get(:@prime)

              matching_field.instance_variable_set(:@prime, new_prime)
              merge_query_recursive(a_query_selection, matching_field)
            else
              b_query.selections << a_query_selection
            end
          end
        end

        # Are two lists of arguments equal?
        def arguments_equal?(a_args, b_args)
          a_args.map { |arg| {name: arg.name, value: arg.value}.to_s }.sort ==
            b_args.map { |arg| {name: arg.name, value: arg.value}.to_s }.sort
        end

        def attach_primes!(query_fields, prime)
          query_fields.each do |field|
            field.instance_variable_set(:@prime, prime)
            attach_primes!(field.children, prime)
          end
        end

        def apply_aliases!(query_selections)
          query_selections.each do |selection|
            unless selection.is_a?(GraphQL::Language::Nodes::InlineFragment)
              prime_factor = selection.instance_variable_get(:@prime)
              selection.alias = "p#{prime_factor}#{selection.name}"
            end

            apply_aliases!(selection.selections)
          end
        end

        # Allows "foo" or "query { foo }"
        def parse(query)
          GraphQL.parse(query)
        rescue GraphQL::ParseError
          GraphQL.parse("query { #{query} }")
        end
      end
    end
  end
end
