require "prime"
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
          fulfill([query, prime], {"data" => filter_keys_on_response(data, prime)})
        end
      end

      def filter_keys_on_response(obj, prime)
        case obj
        when Array
          obj.map { |element| filter_keys_on_response(element, prime) }
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
            filtered_value = filter_keys_on_response(method_value, prime)

            filtered_results[underscore(method_name)] = filtered_value
          end

          filtered_results
        else
          return obj
        end
      end

      def underscore(str)
        str.gsub(/::/, '/').
        gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
        gsub(/([a-z\d])([A-Z])/,'\1_\2').
        tr("-", "_").
        downcase
      end
    end
  end
end
