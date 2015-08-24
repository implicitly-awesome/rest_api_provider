require 'rest_api_provider/version'
require 'validation'
require 'mapper'
require 'requester'
require 'resource'

module RestApiProvider
  class << self
    attr_writer :configuration
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.reset
    @configuration = Configuration.new
  end

  def self.configure
    yield(configuration)
  end

  class Configuration
    attr_accessor :api_root, :verify_ssl, :auth_token, :hateoas_links, :hateoas_href

    def initialize
      @api_root = 'http://'
      @verify_ssl = false
      @auth_token = nil
      @hateoas_links = :links
      @hateoas_href = 'href'
    end
  end

end
