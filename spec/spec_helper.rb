$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'rest_api_provider'
require 'faraday'
require 'webmock/rspec'
require 'rspec/mocks'
WebMock.disable_net_connect!(allow_localhost: true)
