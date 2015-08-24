require 'json'

module RestApiProvider
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
end