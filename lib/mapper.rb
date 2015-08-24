module RestApiProvider
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
end