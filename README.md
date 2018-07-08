# GraphQL Remote Loader
[![Gem Version](https://badge.fury.io/rb/graphql-remote_loader.svg)](https://badge.fury.io/rb/graphql-remote_loader) [![Build Status](https://travis-ci.org/d12/graphql-remote_loader.svg?branch=master)](https://travis-ci.org/d12/graphql-remote_loader)

Performant, batched GraphQL queries from within the resolvers of a [`graphql-ruby`](https://github.com/rmosolgo/graphql-ruby) API.


## Snippet

For default error handling(null if errors) and no post-processing:

```ruby
field :login, String, null: true, description: "The currently authenticated GitHub user's login."

def login
  GitHubLoader.load_value("viewer", "login")
end
```

If you need error handling, post-processing, or complex queries:

```ruby
field :login, String, null: false, description: "The currently authenticated GitHub user's login."

def login
  GitHubLoader.load("viewer { login }").then do |results|
    if results["errors"].present?
      ""
    else
      results["data"]["viewer"]["login"].upcase
    end
  end
end
```

## Full example

To see a working example of how `graphql-remote_loader` works, see the [complete, working example application](https://github.com/d12/graphql-remote_loader_example).

## Description
`graphql-remote_loader` allows for querying GraphQL APIs from within resolvers of a [`graphql-ruby`](https://github.com/rmosolgo/graphql-ruby) API.

This can be used to create GraphQL APIs that depend on data from other GraphQL APIs, either remote or local.

A promise-based resolution strategy from Shopify's [`graphql-batch`](https://github.com/Shopify/graphql-batch) is used to batch all requested data into a single GraphQL query. Promises are fulfilled with only the data they requested.

You can think of it as a lightweight version of schema-stitching.

## How it works

Using GraphQL batch, the loader collects all GraphQL sub-queries before combining and executing one query.

### Merging queries

Once we have all the queries we need, we merge them all together by treating the query ASTs as prefix trees and merging the prefix trees together. For example, if the input queries were `["viewer { foo bar }", "buzz viewer { foo bazz }"]`, then the merged query would be:

```graphql
query{
  buzz
  viewer{
    foo
    bar
    bazz
  }
}
```

### Name conflicts

Suppose we want to merge `["user(login: "foo") { url }", "user(login: "bar") { url }"]`. We can't treat these `user` fields as equal since their arguments don't match, but we also can't naively combine these queries together, the `user` key will be ambiguous.

To solve this problem, we introduce identified aliases. Every query to be merged is given a unique ID. When building the query, we include this unique ID in a new alias on all fields. This prevents conflicts between separate subqueries.

### Fulfilling promises

We only want to fulfill each promise with the data it asked for. This is especially relevant in the case of conflicts as in the case above.

When fulfilling promises, we traverse the result hash and prune out all result keys with UIDs that don't match the query. Before returning the filtered hash, we scrub the UIDs so that the result keys are the same as the GraphQL field names.

This solution prevents all conflict issues and doesn't change the way your API uses this library.

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

```
bundle install
rspec
```
