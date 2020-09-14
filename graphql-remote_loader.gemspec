# coding: utf-8
# frozen_string_literal: true

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'graphql/remote_loader/version'

Gem::Specification.new do |spec|
  spec.name          = "graphql-remote_loader"
  spec.version       = GraphQL::RemoteLoader::VERSION
  spec.authors       = ["Nathaniel Woodthorpe"]
  spec.email         = ["d12@github.com", "njwoodthorpe@gmail.com"]

  spec.summary       = "Performant remote GraphQL queries from within a Ruby GraphQL API."
  spec.description   = "GraphQL::RemoteLoader allows performantly fetching data from remote GraphQL APIs in the resolvers of a graphql-ruby API."
  spec.homepage      = "https://github.com/d12/graphql-remote_loader"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  # spec.bindir        = "bin"
  # spec.executables   = [""]
  spec.require_paths = ["lib"]

  spec.add_dependency "graphql", "~> 1.9"
  spec.add_dependency "graphql-batch", "~> 0.3"

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.6"
  spec.add_development_dependency "pry-byebug", "~> 3.4"
end
