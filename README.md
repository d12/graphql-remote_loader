# GraphQL Remote Loader
Performant, batched GraphQL queries from within the resolvers of a [`graphql-ruby`](https://github.com/rmosolgo/graphql-ruby) API.

## Example

```ruby
  field :repositoryUrl, String, description: "The repository URL"

  def repository_url
    query = <<-GQL
      node(id: "#{obj.global_relay_id}"){
        ... on Repository {
          url
        }
      }
    GQL

    GitHubLoader.load(query).then do |results|
      results["node"]["url"]
    end
  end
```

## Description
`graphql-remote_loader` allows for querying GraphQL APIs from within resolvers of a [`graphql-ruby`](https://github.com/rmosolgo/graphql-ruby) API.

This can be used to create GraphQL APIs that depend on data from other GraphQL APIs, either remote or local.

A promise-based resolution strategy from Shopify's [`graphql-batch`](https://github.com/Shopify/graphql-batch) is used to batch all requested data into a single GraphQL query. Promises are fulfilled with only the data they requested.

You can think of it as a lightweight version of schema-stitching.

## How to use
First, you'll need to install the gem. Either do `gem install graphql-remote_loader` or add this to your Gemfile:

```
gem "graphql-remote_loader"
```

The gem provides a base loader `GraphQL::RemoteLoader::Loader` which does most of the heavy lifting. In order to remain client-agnostic, there's an unimplemented no-op that queries the external GraphQL API.

To use, create a new class that inherits from `GraphQL::RemoteLoader::Loader` and define `def query(query_string)`. The method takes a query String as input. The expected output is a response `Hash`, or some object that responds to `#to_h`.

Example:

```ruby
require "graphql/remote_loader"

module MyApp
  class GitHubLoader < GraphQL::RemoteLoader::Loader
    def query(query_string)
      parsed_query = GraphQLClient.parse(query_string)
      GraphQLClient.query(parsed_query)
    end
  end
end
```

This example uses [`graphql-client`](https://github.com/github/graphql-client). Any client, or even just plain `cURL`/`HTTP` can be used.

## Running tests
There is no setup required to run tests.

```
rspec
```
