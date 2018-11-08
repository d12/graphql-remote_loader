require "prime"
require "json"
require_relative "query_merger"

module GraphQL
  module RemoteLoader
    class Loader < GraphQL::Batch::Loader
      # Delegates to GraphQL::Batch::Loader#load
      # We include a unique prime as part of the batch key to use as part
      # of the alias on all fields. This is used to
      # a) Avoid name collisions in the generated query
      # b) Determine which fields in the result JSON should be
      #    handed fulfilled to each promise
      def self.load(query, context: {}, variables: {})
        @index ||= 1
        @index += 1

        prime = Prime.take(@index - 1).last

        store_context(context)

        interpolate_variables!(query, variables)

        self.for.load([query, prime, @context])
      end

      # Loads the value, then if the query was successful, fulfills promise with
      # the leaf value instead of the full results hash.
      #
      # If errors are present, returns nil.
      def self.load_value(*path, context: {})
        load(query_from_path(path), context: context).then do |results|
          next nil if results["errors"] && !results["errors"].empty?

          value_from_hash(results["data"])
        end
      end

      # Shorthand helper method for #load calls selecting fields off of a `Node` type
      # E.g. `load_on_relay_node("nodeid", "Type", "friends(first: 5) { totalCount }")`
      # is identical to
      # load("node(id: "nodeid") { ... on Type { friends(first: 5) { totalCount } } }")
      def self.load_on_relay_node(node_id, type, selections, context: {})
        query = <<-GRAPHQL
          node(id: \"#{node_id}\") {
            ... on #{type} {
              #{selections}
            }
          }
        GRAPHQL

        load(query, context: context)
      end

      def self.reset_index
        @index = nil
      end

      def self.store_context(context)
        @context ||= {}
        @context.merge!(context.to_h)
      end

      # Given a query string, return a response JSON
      def query(query_string)
        raise NotImplementedError,
          "RemoteLoader::Loader should be subclassed and #query must be defined"
      end

      private

      def perform(queries_and_primes)
        query_string = QueryMerger.merge(queries_and_primes).gsub(/\s+/, " ")
        context = queries_and_primes[-1][-1]
        response = query(query_string, context: context).to_h

        data, errors = response["data"], response["errors"]

        queries_and_primes.each do |query, prime, context|
          response = {}

          response["data"] = filter_keys_on_data(data, prime)

          errors_key = filter_errors(errors, prime)
          response["errors"] = dup(errors_key) unless errors_key.empty?

          scrub_primes_from_error_paths!(response["errors"])

          fulfill([query, prime, context], response)
        end
      end

      # Interpolates variables into the given query.
      # For String variables, surrounds the interpolated string in quotes.
      # To interpolate a String as an Int, Float, or Bool, convert to the appropriate Ruby type.
      #
      # E.g.
      #   interpolate_variables("foo(bar: $my_var)", { my_var: "buzz" })
      #   => "foo(bar: \"buzz\")"
      def self.interpolate_variables!(query, variables = {})
        variables.each do |variable, value|
          case value
          when Integer, Float, TrueClass, FalseClass
            # These types are safe to directly interpolate into the query, and GraphQL does not expect these types to be quoted.
            query.gsub!("$#{variable.to_s}", value.to_s)
          else
            # A string is either a GraphQL String or ID type.
            # This means we need to
            # a) Surround the value in quotes
            # b) escape special characters in the string
            #
            # This else also catches unknown objects, which could break the query if we directly interpolate.
            # These objects get converted to strings, then escaped.

            query.gsub!("$#{variable.to_s}", value.to_s.inspect)
          end
        end
      end

      def dup(hash)
        JSON.parse(hash.to_json)
      end

      def filter_keys_on_data(obj, prime)
        case obj
        when Array
          obj.map { |element| filter_keys_on_data(element, prime) }
        when Hash
          filtered_results = {}

          # Select field keys on the results hash
          fields = obj.keys.select { |k| k.match /\Ap[0-9]+.*[^?]\z/ }

          # Filter methods that were not requested in this sub-query
          fields = fields.select do |field|
            prime_factor = field.match(/\Ap([0-9]+)/)[1].to_i
            (prime_factor % prime) == 0
          end

          # redefine methods on new obj, recursively filter sub-selections
          fields.each do |method|
            method_name = method.match(/\Ap[0-9]+(.*)/)[1]

            method_value = obj[method]
            filtered_value = filter_keys_on_data(method_value, prime)

            filtered_results[underscore(method_name)] = filtered_value
          end

          filtered_results
        else
          return obj
        end
      end

      def filter_errors(errors, prime)
        return [] unless errors

        errors.select do |error|
          # For now, do not support global errors with no path key
          next unless error["path"]

          # We fulfill a promise with an error object if field in the path
          # key was requested by the promise.
          error["path"].all? do |path_key|
            next true if path_key.is_a? Integer

            path_key_prime = path_key.match(/\Ap([0-9]+)/)[1].to_i
            path_key_prime % prime == 0
          end
        end
      end

      def scrub_primes_from_error_paths!(error_array)
        return unless error_array

        error_array.map do |error|
          error["path"].map! do |path_key|
            path_key.match(/\Ap[0-9]+(.*)/)[1]
          end
        end
      end

      def underscore(str)
        str.gsub(/::/, '/').
        gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
        gsub(/([a-z\d])([A-Z])/,'\1_\2').
        tr("-", "_").
        downcase
      end

      def self.query_from_path(path)
        if path.length == 1
          path.first
        else
          "#{path.first} { #{query_from_path(path[1..-1])} }"
        end
      end

      # Input is a hash where all nested hashes have only one key.
      #
      # Output is the leaf at the end of the hash.
      #
      # e.g. {foo: {bar: 5}} => 5
      def self.value_from_hash(hash_or_value)
        case hash_or_value
        when Hash
          # {foo: {bar: 5}}.first[1] => {bar: 5}
          value_from_hash(hash_or_value.first[1])
        else
          hash_or_value
        end
      end
    end
  end
end
