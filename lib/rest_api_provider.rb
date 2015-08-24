require 'rest_api_provider/version'
require 'json'
require 'active_support/inflector'
require 'time'

module RestApiProvider

  # supported data types
  DATA_TYPES = [String, Integer, Fixnum, Bignum, Float, Date, Time, Array, Hash]
  # supported http methods
  HTTP_VERBS = %w(get post put delete)
  # supported model's default methods
  API_METHODS = {all: 'get', grouped: 'get', find: 'get', create: 'post', update: 'put', destroy: 'delete'}

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

  module Validation
    module ClassMethods
      def validates(field_name, options={}, &block)
        @_validations ||= []
        @_validations << {field_name: field_name, options: options, block: block}
      end

      def _validations
        @_validations ||= []
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end

    def valid?
      @errors = Hash.new { |h, k| h[k] = [] }
      self.class._validations.each do |validation|
        value = self.send(validation[:field_name])
        validation[:options].each do |type, options|
          if type == :presence
            if value.class == String
              if value.empty?
                @errors[validation[:field_name]] << 'must be present'
              end
            else
              if value.nil?
                @errors[validation[:field_name]] << 'must be present'
              end
            end
          elsif type == :length
            if options[:within]
              @errors[validation[:field_name]] << "must be within range #{options[:within]}" unless options[:within].include?(value.to_s.length)
            end
            if options[:minimum]
              @errors[validation[:field_name]] << "must be at least #{options[:minimum]} characters long" unless value.to_s.length >= options[:minimum]
            end
            if options[:maximum]
              @errors[validation[:field_name]] << "must be no more than #{options[:minimum]} characters long" unless value.to_s.length <= options[:maximum]
            end
          elsif type == :numericality
            numeric = (true if Float(value) rescue false)
            @errors[validation[:field_name]] << 'must be numeric' unless numeric
          elsif type == :minimum && !value.nil?
            @errors[validation[:field_name]] << "must be at least #{options}" unless value.to_f >= options.to_f
          elsif type == :maximum && !value.nil?
            @errors[validation[:field_name]] << "must be no more than #{options}" unless value.to_f <= options.to_f
          end
        end
        if validation[:block]
          validation[:block].call(self, validation[:field_name], value)
        end
      end
      @errors.empty?
    end

    def errors
      @errors ||= Hash.new { |h, k| h[k] = [] }
    end
  end

  class Mapper
    def self.map2object(response, klass, data_path_elements=[])
      if response && response.body && response.body.any?
        source = response.body
        data_path_elements.each { |elem| source = source[elem] if source[elem] }
        obj = klass.is_a?(Class) ? klass.new : klass
        if obj && source.any?
          source.each do |k, v|
            obj.send("#{k}=", v)
          end
          return obj
        end
      else
        response
      end
    end

    def self.map2array(response, klass, data_path_elements=[])
      if response && response.body && response.body.any?
        result = []
        source = response.body
        data_path_elements.each { |elem| source = source[elem] if source[elem] }
        source.each do |object|
          result << map2object(RestApiProvider::ApiResponse.new(status: response.status, headers: response.headers, body: object), klass)
        end
        return result
      end
      response
    end

    def self.map2hash(response, klass, data_path_elements=[])
      if response && response.body && response.body.any?
        result = {}
        source = response.body
        data_path_elements.each { |elem| source = source[elem] if source[elem] }
        source.each do |group, objects|
          result[group] = []
          objects.each do |object|
            result[group] << map2object(RestApiProvider::ApiResponse.new(status: response.status, headers: response.headers, body: object), klass)
          end
        end
        return result
      end
      response
    end
  end

  class ApiResponse
    attr_reader :status, :headers, :body

    def initialize(status:, headers:, body:)
      @status = status.to_i
      @headers = headers
      begin
        @body = body.is_a?(String) ? JSON.parse(body) : body
      rescue
        @body = nil
      end
    end
  end

  class Requester

    def self.make_request_with(http_verb: HTTP_VERBS.first, url: RestApiProvider.configuration.api_root, verify_ssl: RestApiProvider.configuration.verify_ssl, path: '', content_type: '', params: {}, body: {}, headers: {})
      conn = set_connection(url, verify_ssl)
      request = nil
      response = nil
      begin
        r = conn.send(http_verb) do |req|
          req.url path
          req.headers = headers if headers.any?
          req.headers['Authorization'] = RestApiProvider.configuration.auth_token unless RestApiProvider.configuration.auth_token.nil?
          req.headers['Content-Type'] = content_type
          req.params = params if params.any?
          req.body = body.to_json if body.any?
          request = req
        end
        response = RestApiProvider::ApiResponse.new(status: r.status, headers: r.headers, body: r.body)
      rescue StandardError => e
        raise RestApiProvider::ApiError.new(request, r), (r.body if r)
      end
      if (100...400).to_a.include?(r.status)
        response
      else
        raise RestApiProvider::ApiError.new(request, response), (response.body if response)
      end
    end

    private

    def self.set_connection(url, verify_ssl)
      # todo: deal with SSL
      Faraday.new(url: url, :ssl => {:verify => verify_ssl}) do |faraday|
        # todo: deal with async
        faraday.adapter Faraday.default_adapter
        # faraday.response :json
      end
    end
  end

  class ApiError < StandardError
    attr_reader :request, :response

    def initialize(request, response)
      @request = request
      @response = response
    end
  end

  class Resource
    include RestApiProvider::Validation

    # class instance variables + class instance methods .field, .set_path
    module ClassMethods

      def resource_path(path)
        @_path = path
      end

      def path
        @_path || "/#{self.name.underscore.pluralize.downcase}/:slug"
      end

      def content_type(content)
        @_content = content unless content.to_s.strip.empty?
      end

      def content
        @_content || 'application/json'
      end

      def fields
        @_fields ||= {}
      end

      def field(name, type: nil, default: nil)
        if type && !RestApiProvider::DATA_TYPES.include?(type)
          raise TypeError, "Unsupported type. Expected one of: #{RestApiProvider::DATA_TYPES.to_s}"
        end
        name = name.underscore.to_sym if name.is_a? String
        fields[name] = {type: type, default: default}
      end

      def relations
        @_relations ||= {}
      end

      def set_relation_cache(key, value)
        @_relations[key][:cache] = value
      end

      def enable_relations_caching
        @_enable_relations_caching = true
      end

      def relations_caching_enabled?
        @_enable_relations_caching.nil? ? false : true
      end

      def clear_cache
        @_relations.values.each{|r| r[:cache] = nil}
      end

      def has_one(resource_name, rel: nil, data_path: '', type: nil)
        if [String, Symbol].include? resource_name.class
          relation_name = resource_name.to_s
          rel ||= resource_name.is_a?(Symbol) ? resource_name.to_s : resource_name
          relations[relation_name] = {type: :one2one, rel: rel, data_path: data_path, klass: (type || relation_name.classify.constantize), cache: nil}
        else
          raise ArgumentError.new 'Resource name should be either String or Symbol.'
        end
      end

      alias_method :belongs_to, :has_one

      def has_many(resource_name, rel: nil, data_path: '', type: nil)
        if [String, Symbol].include? resource_name.class
          relation_name = resource_name.to_s
          rel ||= resource_name.is_a?(Symbol) ? resource_name.to_s : resource_name
          relations[relation_name] = {type: :one2many, rel: rel, data_path: data_path, klass: (type || relation_name.classify.constantize), cache: nil}
        else
          raise ArgumentError.new 'Resource name should be either String or Symbol.'
        end
      end

      def define_default_fields
        # define 'links' field based on configuration name
        hateoas_links = RestApiProvider.configuration.hateoas_links
        name = hateoas_links.is_a?(String) ? hateoas_links.underscore.to_sym : hateoas_links
        fields[name] = {type: nil, default: nil}
      end

    end

    # inject class instance variables & methods into Entity subclass
    def self.inherited(subclass)
      subclass.extend(ClassMethods)
      # define a default fields
      subclass.define_default_fields
    end

    # predefined api methods: .all, .grouped, .find, .create, .update, .destroy
    RestApiProvider::API_METHODS.each do |method_name, verb|
      # define class singleton method with given name
      define_singleton_method(method_name) do |slugs: {}, params: {}, body: {}, headers: {}|
        request_path = path.clone
        # fill the common path with given slugs
        # if slugs were given - replace :slug masks with proper values
        if slugs.any?
          slugs.each do |k, v|
            request_path.gsub!(/:#{k.to_s}/, v || '')
          end
          # or just clear path from the first :slug occuring
        else
          request_path.gsub!(/:.+/, '')
        end
        # make a request, get a json
        resp = RestApiProvider::Requester.make_request_with http_verb: verb, path: request_path, content_type: content, params: params, body: body, headers: headers
        # map json to the model objects array
        if method_name == :all
          # map & return the array
          RestApiProvider::Mapper.map2array(resp, self)
          # map json to the hash where model objects grouped by hash keys
        elsif method_name == :grouped
          RestApiProvider::Mapper.map2hash(resp, self)
          # map json to the model object
        else
          # map & return the model object
          RestApiProvider::Mapper.map2object(resp, self)
        end
      end
    end

    # .get, .post, .put, .delete methods
    RestApiProvider::HTTP_VERBS.each do |verb|
      # define class singleton methods which will define concrete class singleton methods
      define_singleton_method(verb) do |method_name, custom_path=nil, result: self, data_path: ''|
        # get a name of future method
        method_name = method_name.underscore.to_sym if method_name.is_a? String
        # define class singleton method with name constructed earlier
        define_singleton_method(method_name) do |slugs: {}, params: {}, body: {}, headers: {}|
          # if path defined - override common path
          request_path = custom_path ? custom_path.clone : path.clone
          # fill the path with given slugs
          # if slugs were given - replace :slug masks with proper values
          if slugs.any?
            slugs.each do |k, v|
              request_path.gsub!(/:#{k.to_s}/, v || '')
            end
            # or just clear path from the first :slug occuring
          else
            request_path.gsub!(/:.+/, '')
          end
          # make a request, get a json
          resp = RestApiProvider::Requester.make_request_with http_verb: verb, path: request_path, content_type: content, params: params, body: body, headers: headers
          # get an array of elements of path to data source element
          data_path_elements = data_path.split('/').select { |x| !x.strip.empty? }
          # map json to a proper object
          case result.name
            when 'Array'
              RestApiProvider::Mapper.map2array(resp, self, data_path_elements)
            when 'Hash'
              RestApiProvider::Mapper.map2hash(resp, self, data_path_elements)
            else
              RestApiProvider::Mapper.map2object(resp, self, data_path_elements)
          end
        end
      end
    end

    # attributes of model object
    attr_accessor :attributes

    # model instance constructor
    def initialize(attrs={})
      # model attributes stored in hash based on model's class field definitions {field_name:default_value}
      @attributes = Hash[self.class.fields.map { |k, v| [k, v[:default]] }]
      # if some attributes were given in constructor - add them into hash and into model's class fields (in respect of consistency)
      attrs.each do |k, v|
        @attributes[k] = v
        self.class.field(k, type: v.class, default: v)
      end
    end

    def method_missing(name, *args)
      key = name.to_s
      # if method name has = sign at the end (a=,b =, etc.)
      if key =~ /=$/
        handle_field_setter key, *args
      # if method name has not = sign at the end (a,b, etc.)
      else
        handle_field_getter key, *args
      end
    end

    private

    def handle_field_getter(key, *args)
      # get a method name
      key = key.underscore.to_sym
      # if attribute exists (and a proper field was defined in the model's class) - just return it
      if self.class.fields.key?(key)
        @attributes[key]
      # maybe it's a relationship? if so - should request for
      else
        handle_relation_getter key, *args
      end
    end

    def handle_field_setter(key, *args)
      # get the method name without '=' sign
      key = key.chop.underscore.to_sym
      # if we've defined a proper field in model (entity) class
      if self.class.fields.key?(key)
        # if field's type was specified (explicitly)
        if !self.class.fields[key][:type].nil?
          case self.class.fields[key][:type].name
            when 'String'
              @attributes[key] = args[0].to_s
            when 'Integer', 'Fixnum', 'Bignum'
              begin
                @attributes[key] = args[0].is_a?(Integer) ? args[0] : Integer(args[0])
              rescue
                # do nothing
              end
            when 'Float'
              begin
                @attributes[key] = args[0].is_a?(Float) ? args[0] : Float(args[0])
              rescue
                # do nothing
              end
            when 'Date'
              begin
                @attributes[key] = args[0].is_a?(Date) ? args[0] : Date.parse(args[0])
              rescue
                # do nothing
              end
            when 'Time'
              begin
                @attributes[key] = args[0].is_a?(Time) ? args[0] : Time.parse(args[0])
              rescue
                # do nothing
              end
            when 'Array', 'Hash'
              begin
                @attributes[key] = JSON.parse(args[0].to_json)
              rescue
                # do nothing
              end
            else
              # given type is not supported by implicit casting
              raise TypeError, "Unsupported type. Expected one of: #{RestApiProvider::DATA_TYPES.to_s}, given: #{args[0].class}"
          end
        else
          # else assign a value as-is
          begin
            @attributes[key] = JSON.parse(args[0].to_json)
          rescue
            @attributes[key] = args[0]
          end
        end
      end

    end

    def handle_relation_getter(key, *args)
      key = key.to_s
      if self.class.relations.key?(key)
        relation = self.class.relations[key]
        # if related resource already was saved in :cache, caching enabled and true argument was provided - return it immediately
        if self.class.relations_caching_enabled? && args.include?(true) && relation[:cache]
          return relation[:cache]
        end
        # try to find links attribute in the resource
        hateoas_links = RestApiProvider.configuration.hateoas_links.is_a?(String) ? RestApiProvider.configuration.hateoas_links.underscore.to_sym : RestApiProvider.configuration.hateoas_links
        hateoas_href = RestApiProvider.configuration.hateoas_href.is_a?(Symbol) ? RestApiProvider.configuration.hateoas_href.to_s : RestApiProvider.configuration.hateoas_href
        rel = relation[:rel]
        href = if @attributes[hateoas_links]
                 @attributes[hateoas_links][rel][hateoas_href] if @attributes[hateoas_links][rel]
               end
        if href
          # make a GET request with exact url (which should point to related resource/s)
          resp = RestApiProvider::Requester.make_request_with http_verb: RestApiProvider::HTTP_VERBS.first, url: href
          # get an array of elements of path to data source element
          data_path_elements = relation[:data_path].split('/').select { |x| !x.strip.empty? }
          # if relation is one-to-many - we should map the response to Array of related resource's class
          # which in relations storage presented as class.name string
          if relation[:type] == :one2many
            obj = RestApiProvider::Mapper.map2array(resp, relation[:klass], data_path_elements)
          else
            obj = RestApiProvider::Mapper.map2object(resp, relation[:klass], data_path_elements)
          end
          # write into cache if relations caching enabled
          self.class.set_relation_cache(key, obj) if self.class.relations_caching_enabled?
          obj
        end
      end
    end
  end

end
