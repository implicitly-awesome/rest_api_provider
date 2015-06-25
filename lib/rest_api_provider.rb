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
    attr_accessor :api_root, :auth_token

    def initialize
      @api_root = 'http://'
      @auth_token = nil
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

  class JsonMapper

    def self.map2object(json, klass, data_path_elements=[])
      begin
        source = json.is_a?(String) ? JSON.parse(json) : json
      rescue
        return nil
      end
      data_path_elements.each { |elem| source = source[elem] if source[elem] }
      obj = klass.is_a?(Class) ? klass.new : klass
      if obj && source.any?
        source.each do |k, v|
          obj.send("#{k}=", v)
        end
        return obj
      end
      nil
    end

    def self.map2array(json, klass, data_path_elements=[])
      result = []
      begin
        json = JSON.parse(json) if json.is_a? String
      rescue
        result
      end
      data_path_elements.each { |elem| json = json[elem] if json[elem] }
      json.each do |json_hash|
        result << map2object(json_hash, klass)
      end
      result
    end

    def self.map2hash(json, klass, data_path_elements=[])
      result = {}
      begin
        json = JSON.parse(json) if json.is_a? String
      rescue
        result
      end
      data_path_elements.each { |elem| json = json[elem] if json[elem] }
      json.each do |group, objects|
        result[group] = []
        objects.each do |object|
          result[group] << map2object(object, klass)
        end
      end
      result
    end
  end

  class Requester

    def self.make_request_with(http_verb: HTTP_VERBS.first, path: '', content_type:'', params: {}, body: {}, headers: {})
      conn = set_connection
      request = nil
      begin
        resp = conn.send(http_verb) do |req|
          req.url path
          req.headers = headers if headers.any?
          req.headers['Authorization'] = RestApiProvider.configuration.auth_token unless RestApiProvider.configuration.auth_token.nil?
          req.headers['Content-Type'] = content_type
          req.params = params if params.any?
          req.body = body.to_json if body.any?
          request = req
        end
      rescue StandardError => e
        raise RestApiProvider::ApiError.new(500, request), e.message
      end
      if (100...400).to_a.include?(resp.status)
        resp.body
      else
        raise RestApiProvider::ApiError.new(resp.status, request), resp.body
      end
    end

    private

    def self.set_connection
      # todo: deal with SSL
      Faraday.new(url: RestApiProvider.configuration.api_root, :ssl => {:verify => false}) do |faraday|
        # todo: deal with async
        faraday.adapter Faraday.default_adapter
        # faraday.response :json
      end
    end
  end

  class ApiError < StandardError
    attr_reader :status, :request

    def initialize(status, request)
      @status = status
      @request = request
    end
  end

  class Resource
    include RestApiProvider::Validation

    # class instance variables + class instance methods .field, .set_path
    module ClassMethods

      # set path
      def resource_path(path)
        @path = path
      end

      # set content type
      def content_type(content)
        @content = content unless content.to_s.strip.empty?
      end

      def field(name, type: nil, default: nil)
        if type && !RestApiProvider::DATA_TYPES.include?(type)
          raise TypeError, "Unsupported type. Expected one of: #{RestApiProvider::DATA_TYPES.to_s}"
        end
        name = name.underscore.to_sym if name.is_a? String
        fields[name] = {type: type, default: default}
      end

      def fields
        @_fields ||= {}
      end
    end

    def self.path
      @path || "/#{self.name.to_s.underscore.pluralize.downcase}/:slug"
    end

    def self.content
      @content || 'application/json'
    end

    # inject class instance variables & methods into Entity subclass
    def self.inherited(subclass)
      subclass.extend(ClassMethods)
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
        request_path = nil
        # map json to the model objects array
        if method_name == :all
          # map & return the array
          RestApiProvider::JsonMapper.map2array(resp, self)
          # map json to the hash where model objects grouped by hash keys
        elsif method_name == :grouped
          RestApiProvider::JsonMapper.map2hash(resp, self)
          # map json to the model object
        else
          # map & return the model object
          RestApiProvider::JsonMapper.map2object(resp, self)
        end
      end
    end

    # .get, .post, .put, .delete methods
    RestApiProvider::HTTP_VERBS.each do |verb|
      # define class singleton methods which will define concrete class singleton methods
      define_singleton_method(verb) do |method_name, custom_path=nil, result:self, data_path:''|
        # get a name of future method
        method_name = method_name.underscore.to_sym if method_name.is_a? String
        # define class singleton method with name constructed earlier
        define_singleton_method(method_name) do |slugs: {}, params: {}, body: {}, headers: {}|
          # if path defined - override common path
          request_path = custom_path || path.clone
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
          data_path_elements = data_path.split('/').select{|x| !x.strip.empty?}
          # map json to a proper object
          case result.name
            when 'Array'
              RestApiProvider::JsonMapper.map2array(resp, self, data_path_elements)
            when 'Hash'
              RestApiProvider::JsonMapper.map2hash(resp, self, data_path_elements)
            else
              RestApiProvider::JsonMapper.map2object(resp, self, data_path_elements)
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
        # get the method name without = sign
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
                  @attributes[key] = Integer(args[0])
                rescue
                  # do nothing
                end
              when 'Float'
                begin
                  @attributes[key] = Float(args[0])
                rescue
                  # do nothing
                end
              when 'Date'
                begin
                  @attributes[key] = Date.parse(args[0])
                rescue
                  # do nothing
                end
              when 'Time'
                begin
                  @attributes[key] = Time.parse(args[0])
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
        # if method name has not = sign at the end (a,b, etc.)
      else
        # get a method name
        key = key.underscore.to_sym
        # if attribute exists (and a proper field was defined in the model's class) - just return it
        @attributes[key] if self.class.fields.key?(key)
      end
    end
  end

end
