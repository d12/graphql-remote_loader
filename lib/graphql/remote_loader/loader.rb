# frozen_string_literal: true

require "json"
require_relative "query_merger"

module GraphQL
  module RemoteLoader
    class Loader < GraphQL::Batch::Loader
      # Delegates to GraphQL::Batch::Loader#load
      # We include a unique id as part of the batch key to use as part
      # of the alias on all fields. This is used to
      # a) Avoid name collisions in the generated query
      # b) Determine which fields in the result JSON should be
      #    handed fulfilled to each promise
      def self.load(query, context: {}, variables: {})
        @index ||= 0
        @index += 1

        store_context(context)

        self.for.load([interpolate_variables(query, variables), @index, @context])
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

      def perform(queries_and_ids)
        query_string = QueryMerger.merge(queries_and_ids).gsub(/\s+/, " ")
        context = queries_and_ids[-1][-1]
        response = query(query_string, context: context).to_h

        data, errors = response["data"], response["errors"]

        queries_and_ids.each do |query, caller_id, context|
          response = {}

          response["data"] = filter_keys_on_data(data, caller_id)

          errors_key = filter_errors(errors, caller_id)
          response["errors"] = dup(errors_key) unless errors_key.empty?

          scrub_caller_ids_from_error_paths!(response["errors"])

          fulfill([query, caller_id, context], response)
        end
      end

      # Interpolates variables into the given query.
      # For String variables, surrounds the interpolated string in quotes.
      # To interpolate a String as an Int, Float, or Bool, convert to the appropriate Ruby type.
      #
      # E.g.
      #   interpolate_variables("foo(bar: $my_var)", { my_var: "buzz" })
      #   => "foo(bar: \"buzz\")"
      def self.interpolate_variables(query, variables = {})
        query.dup.tap { |mutable_query| interpolate_variables!(mutable_query, variables) }
      end

      def self.interpolate_variables!(query, variables = {})
        variables.each { |variable, value| query.gsub!("$#{variable.to_s}", stringify_variable(value)) }
      end

      def self.stringify_variable(value)
        case value
        when Integer, Float, TrueClass, FalseClass
          # These types are safe to directly interpolate into the query, and GraphQL does not expect these types to be quoted.
          value.to_s
        when Array
          # Arrays can contain elements with various types, so we need to check them one by one
          stringified_elements = value.map { |element| stringify_variable(element) }
          "[#{stringified_elements.join(', ')}]"
        when Hash
          # Hashes can contain values with various types, so we need to check them one by one
          stringified_key_value_pairs = value.map { |key, value| "#{key}: #{stringify_variable(value)}" }
          "{#{stringified_key_value_pairs.join(', ')}}"
        else
          # A string is either a GraphQL String or ID type.
          # This means we need to
          # a) Surround the value in quotes
          # b) escape special characters in the string
          #
          # This else also catches unknown objects, which could break the query if we directly interpolate.
          # These objects get converted to strings, then escaped.

          value.to_s.inspect
        end
      end

      def dup(hash)
        JSON.parse(hash.to_json)
      end

      def filter_keys_on_data(obj, caller_id)
        case obj
        when Array
          obj.map { |element| filter_keys_on_data(element, caller_id) }
        when Hash
          filtered_results = {}

          # Select field keys on the results hash
          fields = obj.keys.select { |k| k.match /\Ap[0-9]+.*[^?]\z/ }

          # Filter methods that were not requested in this sub-query
          fields = fields.select do |field|
            graphql_caller = field.match(/\Ap([0-9]+)/)[1].to_i
            graphql_caller[caller_id] == 1 # Fixnum#[] accesses bitwise representation of num
          end

          # redefine fields on new obj, recursively filter sub-selections
          fields.each do |field|
            field_name = field.match(/\Ap[0-9]+(.*)/)[1]

            value = obj[field]
            filtered_results[underscore(field_name)] = filter_keys_on_data(value, caller_id)
          end

          filtered_results
        else
          # Base case, no more recursion needed.
          return obj
        end
      end

      def filter_errors(errors, caller_id)
        return [] unless errors

        errors.select do |error|
          # For now, do not support global errors with no path key
          next unless error["path"]

          # We fulfill a promise with an error object if field in the path
          # key was requested by the promise.
          error["path"].all? do |path_key|
            next true if path_key.is_a? Integer

            path_key_caller_id = path_key.match(/\Ap([0-9]+)/)[1].to_i
            path_key_caller_id[caller_id]
          end
        end
      end

      def scrub_caller_ids_from_error_paths!(error_array)
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
