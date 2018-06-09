module GraphQL
  module RemoteLoader

    # Given a list of queries and their prime UIDs, generate the merged and labeled
    # GraphQL query to be sent off to the remote backend.
    class QueryMerger
      class << self
        def merge(queries_and_primes)
          new_ast = []

          queries_and_primes.each do |query, prime|
            parsed_query = [parse(query)]
            attach_primes!(parsed_query, prime)
            merge_query(parsed_query, new_ast)
          end

          query_string_from_ast(new_ast)
        end

        private

        def merge_query(query, ast)
          query.each do |query_field|
            matching_field = ast.find do |ast_field|
              query_field[:field] == ast_field[:field] &&
                query_field[:arguments] == ast_field[:arguments]
            end

            if matching_field
              matching_field[:primes] *= query_field[:primes]
              merge_query(query_field[:body], matching_field[:body])
            else
              ast << query_field
            end
          end
        end

        def attach_primes!(query, prime)
          query.each do |field|
            field[:primes] = prime
            attach_primes!(field[:body], prime)
          end
        end

        def query_string_from_ast(ast)
          ast_node_strings = ast.map do |ast_node|
            query_string_for_node(ast_node)
          end.join(" ")
          ast_node_strings
        end

        def query_string_for_node(node)
          field = node[:field]

          # TODO: This won't work for fields named `query`. Fix once
          # I move to Roberts non-jank parser
          unless field.include?("...") || field == "query"
            # assign preix if not a spread
            field = "p#{node[:primes]}#{field}: #{field}"
          end

          args = node[:arguments].map do |arg, value|
            value = "\"#{value}\"" if value.is_a? String

            "#{arg}: #{value}"
          end

          arg_string = unless args.empty?
            "(#{args.join(",")})"
          else
            ""
          end

          body_string = unless node[:body].empty?
            str = node[:body].map do |node|
              query_string_for_node(node)
            end

            "{ #{str.join(" ")} }"
          end

          "#{field}#{arg_string} #{body_string}".strip
        end

        def parse(query)
          tokenizer = QueryTokenizer.new("query { #{query} }")
          QueryAST.build(tokenizer)
        end

        class QueryAST
          class ParseException < Exception; end

          class << self
            def build(tokenizer)
              result = build_node(tokenizer)
            end

            def build_node(tokenizer)
              {
                field: get_field(tokenizer),
                arguments: get_args(tokenizer),
                body: build_body(tokenizer)
              }
            end

            def get_field(tokenizer)
              token = tokenizer.pop

              if token[:type] == :spread
                validate_token_type(tokenizer.pop, :on)
                spread_type = tokenizer.pop[:string]

                return "... on #{spread_type}"
              end

              validate_token_type(token, :field)

              throw_parse_exception(token, "field") unless (token[:type] == :field)

              token[:string]
            end

            def get_args(tokenizer)
              args = {}
              return args unless (tokenizer.peek[:type] == :left_paren)

              # remove "("
              tokenizer.pop

              while true
                token = tokenizer.pop
                validate_token_type(token, :key)

                # Remove :
                key = token[:string].sub(":", "")

                token = tokenizer.pop
                value = case token[:type]
                        when :string
                          token[:string][1..-2] # remove ""
                        when :int
                          Integer(token[:string])
                        when :float
                          Float(token[:string])
                        when :true
                          true
                        when :false
                          false
                        else
                          raise ParseException, "Expected string, int, float, or boolean, got #{token[:string]}"
                        end

                args[key.to_sym] = value

                if tokenizer.peek[:type] == :comma
                  tokenizer.pop
                elsif tokenizer.peek[:type] == :right_paren
                  tokenizer.pop
                  break
                else
                  raise ParseException, "Expected comma or right paren, got #{tokenizer[:string]}"
                end
              end

              args
            end

            def build_body(tokenizer)
              body = []
              return body unless (tokenizer.peek[:type] == :left_brace)

              # remove "{"
              tokenizer.pop

              while true
                body << build_node(tokenizer)
                break if (tokenizer.peek[:type] == :right_brace)
              end

              # remove "}"
              tokenizer.pop

              body
            end

            def validate_token_type(token, expected_type)
              unless token[:type] == expected_type
                raise ParseException, "Expected #{expected_type.to_s} token, got #{token[:string]}"
              end
            end
          end
        end

        class QueryTokenizer
          def initialize(query)
            @query = query.chars
            set_next_token
          end

          # Get next token, without removing from stream
          def peek
            @next_token
          end

          # Pop next token
          def pop
            token = @next_token
            set_next_token if token

            token
          end

          private

          # Read @query to set @next_token
          def set_next_token
            next_token_string = extract_token_string_from_query
            @next_token = tokenize_string(next_token_string)
          end

          def extract_token_string_from_query
            trim_leading_whitespace

            token_string = ""
            while true
              next_char = @query.first || break

              if is_brace_or_bracket_or_comma?(next_char)
                if token_string.length == 0
                  token_string << @query.shift
                end

                break
              else
                if !is_whitespace?(@query.first)
                  token_string << @query.shift
                else
                  break
                end
              end
            end

            token_string
          end

          def tokenize_string(next_token_string)
            token = case next_token_string
            when '{'
              :left_brace
            when '}'
              :right_brace
            when '('
              :left_paren
            when ')'
              :right_paren
            when ','
              :comma
            when /\A[[:digit:]]+\z/
              :int
            when /\A[[:digit:]]+\.[[:digit:]]+\z/
              :float
            when 'true'
              :true
            when 'false'
              :false
            when 'on'
              :on
            when /\A".*"\z/
              :string
            when /\A.+:\z/
              :key
            when ''
              next_token_string = "END OF STREAM"
              :empty
            when '...'
              :spread
            else
              :field
            end

            { type: token, string: next_token_string }
          end

          def trim_leading_whitespace
            while is_whitespace?(@query.first)
              @query.shift
            end
          end

          def is_whitespace?(char)
            char == "\n" || char == " "
          end

          def is_brace_or_bracket_or_comma?(char)
            char == "{" || char == "}" || char == "(" || char == ")" || char == ","
          end
        end
      end
    end
  end
end
