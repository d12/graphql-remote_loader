module GraphQL
  module RemoteLoader
    # Given a list of queries and their prime UIDs, generate the merged and labeled
    # GraphQL query to be sent off to the remote backend.
    class QueryMerger
      class << self
        def merge(queries_and_primes)
          parsed_queries = queries_and_primes.map do |query, prime|
            parsed_query = parse(query)

            parsed_query.definitions.each do |definition|
              attach_primes!(definition.children, prime)
            end

            parsed_query
          end

          merge_parsed_queries(parsed_queries).to_query_string
        end

        private

        def merge_parsed_queries(parsed_queries)
          merged_query = parsed_queries.pop

          parsed_queries.each do |query|
            merge_query_recursive(query.definitions[0], merged_query.definitions[0])
            merge_fragment_definitions(query, merged_query)
          end

          merged_query.definitions.each do |definition|
            apply_aliases!(definition.selections)
          end

          merged_query
        end

        # merges a_query's fragment definitions into b_query
        def merge_fragment_definitions(a_query, b_query)
          a_query.definitions[1..-1].each do |a_definition|
            matching_fragment_definition = b_query.definitions.find do |b_definition|
              a_definition.name == b_definition.name
            end

            if matching_fragment_definition
              merge_query_recursive(a_definition, matching_fragment_definition)
            else
              b_query.definitions << a_definition
            end
          end
        end

        # merges a_query into b_query
        def merge_query_recursive(a_query, b_query)
          exempt_node_types = [
            GraphQL::Language::Nodes::InlineFragment,
            GraphQL::Language::Nodes::FragmentSpread
          ]

          a_query.selections.each do |a_query_selection|
            matching_field = b_query.selections.find do |b_query_selection|
              next false if (a_query_selection.is_a? GraphQL::Language::Nodes::InlineFragment) &&
                (b_query_selection.is_a? GraphQL::Language::Nodes::InlineFragment)

              same_name = a_query_selection.name == b_query_selection.name

              next same_name if exempt_node_types.any? { |type| b_query_selection.is_a?(type) }

              same_args = arguments_equal?(a_query_selection, b_query_selection)
              same_alias = a_query_selection.alias == b_query_selection.alias

              same_name && same_args && same_alias
            end

            if matching_field
              new_prime = matching_field.instance_variable_get(:@prime) *
                a_query_selection.instance_variable_get(:@prime)

              matching_field.instance_variable_set(:@prime, new_prime)
              merge_query_recursive(a_query_selection, matching_field) unless exempt_node_types.any? { |type| matching_field.is_a?(type) }
            else
              b_query.selections << a_query_selection
            end
          end
        end

        # Are two lists of arguments equal?
        def arguments_equal?(a, b)
          # Return true if both don't have args.
          # Return false if only one doesn't have args
          return true unless a.respond_to?(:arguments) && b.respond_to?(:arguments)
          return false unless a.respond_to?(:arguments) || b.respond_to?(:arguments)

          a.arguments.map { |arg| {name: arg.name, value: arg.value}.to_s }.sort ==
            b.arguments.map { |arg| {name: arg.name, value: arg.value}.to_s }.sort
        end

        def attach_primes!(query_fields, prime)
          query_fields.each do |field|
            field.instance_variable_set(:@prime, prime)
            attach_primes!(field.children, prime)
          end
        end

        def apply_aliases!(query_selections)
          exempt_node_types = [
            GraphQL::Language::Nodes::InlineFragment,
            GraphQL::Language::Nodes::FragmentSpread
          ]

          query_selections.each do |selection|
            unless exempt_node_types.any? { |type| selection.is_a? type }
              prime_factor = selection.instance_variable_get(:@prime)

              selection.alias = if selection.alias
                "p#{prime_factor}#{selection.alias}"
              else
                "p#{prime_factor}#{selection.name}"
              end
            end

            # Some nodes don't have selections (e.g. fragment spreads)
            apply_aliases!(selection.selections) if selection.respond_to? :selections
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
