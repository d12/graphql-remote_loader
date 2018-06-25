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
      def self.load(query)
        @index ||= 1
        @index += 1

        prime = Prime.take(@index - 1).last

        self.for.load([query, prime])
      end

      # Loads the value, then if the query was successful, fulfills promise with
      # the leaf value instead of the full results hash.
      #
      # If errors are present, returns nil.
      def self.load_value(*path)
        load(query_from_path(path)).then do |results|
          next nil if results["errors"] && !results["errors"].empty?

          value_from_hash(results["data"])
        end
      end

      def self.reset_index
        @index = nil
      end

      # Given a query string, return a response JSON
      def query(query_string)
        raise NotImplementedError,
          "RemoteLoader::Loader should be subclassed and #query must be defined"
      end

      private

      def perform(queries_and_primes)
        query_string = QueryMerger.merge(queries_and_primes)
        response = query(query_string).to_h

        data, errors = response["data"], response["errors"]

        queries_and_primes.each do |query, prime|
          response = {}

          response["data"] = filter_keys_on_data(data, prime)

          errors_key = filter_errors(errors, prime)
          response["errors"] = dup(errors_key) unless errors_key.empty?

          scrub_primes_from_error_paths!(response["errors"])

          fulfill([query, prime], response)
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
