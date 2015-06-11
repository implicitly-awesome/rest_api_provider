require 'rest_api_provider/version'
require 'json'

module RestApiProvider

  # supported data types
  DATA_TYPES = [String, Integer, Fixnum, Bignum, Float, Date, Array, Hash]
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
    attr_accessor :api_root, :basic_auth_token

    def initialize
      @api_root = 'http://'
      @basic_auth_token = nil
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
            if value.nil?
              @errors[validation[:field_name]] << 'must be present'
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

    def self.map2object(json, obj)
      json_hash = json.is_a?(String) ? JSON.parse(json) : json
      if obj && json_hash.any?
        json_hash.each do |k, v|
          obj.send("#{k}=", v)
        end
        return obj
      end
      nil
    end

    def self.map2array(json, klass)
      json = JSON.parse(json) if json.is_a? String
      result = []
      json.each do |json_hash|
        result << map2object(json_hash, klass.new)
      end
      result
    end

    def self.map2hash(json, klass)
      json = JSON.parse(json) if json.is_a? String
      result = {}
      json.each do |group, objects|
        result[group] = []
        objects.each do |object|
          result[group] << map2object(object, klass.new)
        end
      end
      result
    end
  end

  class Requester

    def self.make_request_with(http_verb: HTTP_VERBS.first, path: '', params: {}, body: {}, headers: {})
      conn = set_connection
      request = nil
      begin
        resp = conn.send(http_verb) do |req|
          req.url path
          req.headers = headers if headers.any?
          req.params = params if params.any?
          req.body = body.to_json if body.any?
          request = req
        end
      rescue StandardError => e
        raise RestApiProvider::ApiError.new(500, request), e.message
      end
      if resp.status == 200
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
        @path = path || self.name.to_s.pluralize.downcase
      end

      def field(name, type: String, default: nil)
        unless RestApiProvider::DATA_TYPES.include?(type)
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
      @path
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
        resp = RestApiProvider::Requester.make_request_with http_verb: verb, path: request_path, params: params, body: body, headers: headers
        # map json to the model objects array
        if method_name == :all
          # map & return the array
          RestApiProvider::JsonMapper.map2array(resp, self)
          # map json to the hash where model objects grouped by hash keys
        elsif method_name == :grouped
          RestApiProvider::JsonMapper.map2hash(resp, self)
          # map json to the model object
        else
          # create a model object
          model = self.new
          # map & return the model object
          RestApiProvider::JsonMapper.map2object(resp, model)
        end
      end
    end

    # .get, .post, .put, .delete methods
    RestApiProvider::HTTP_VERBS.each do |verb|
      # define class singleton methods which will define concrete class singleton methods
      define_singleton_method(verb) do |method_name, custom_path=''|
        # get a name of future method
        method_name = method_name.underscore.to_sym if method_name.is_a? String
        # if path defined - override common path
        request_path = custom_path || path
        # define class singleton method with name constructed earlier
        define_singleton_method(method_name) do |slugs: {}, params: {}, body: {}, headers: {}|
          # create a model object
          model = self.new
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
          resp = RestApiProvider::Requester.make_request_with http_verb: verb, path: request_path, params: params, body: body, headers: headers
          # map json to the model object
          RestApiProvider::JsonMapper.map2object(resp, model)
          # return the model object
          model
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
        key = RestApiProvider.underscore(key.chop).to_sym
        # if we've defined a proper field in model (entity) class
        if self.class.fields.key?(key)
          # if earlier defined field has such data type as assigned value
          if args[0].is_a?(self.class.fields[key][:type])
            # just store the value of the model's attribute
            @attributes[key] = args[0]
            # or try to cast types, if error occurs - do nothing (just will not store the value)
          else
            case self.class.fields[key][:type].to_s
              when 'String'
                @attributes[key] = args[0] # json always provides strings
              when 'Integer'
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
              else
                # given type is not supported by implicit casting
                raise TypeError, "Unsupported type. Expected one of: #{RestApiProvider::DATA_TYPES.to_s}, given: #{args[0].class}"
            end
          end
        end
        # if method name has not = sign at the end (a,b, etc.)
      else
        # get a method name
        key = RestApiProvider.underscore(key).to_sym
        # if attribute exists (and a proper field was defined in the model's class) - just return it
        @attributes[key] if self.class.fields.key?(key)
      end
    end
  end

  private

  def self.underscore(camel_cased_word)
    return camel_cased_word unless camel_cased_word =~ /[A-Z-]|::/
    word = camel_cased_word.to_s.gsub('::'.freeze, '/'.freeze)
    word.gsub!(/(?:(?<=([A-Za-z\d]))|\b)(#{inflections.acronym_regex})(?=\b|[^a-z])/) { "#{$1 && '_'}#{$2.downcase}" }
    word.gsub!(/([A-Z\d]+)([A-Z][a-z])/,'\1_\2')
    word.gsub!(/([a-z\d])([A-Z])/,'\1_\2')
    word.tr!('-', '_')
    word.downcase!
    word
  end

end
