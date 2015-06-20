# REST API Provider
Simple REST API Provider implements an abstract which allows you to make a requests to REST API, get a response and map it to your POCO class object (RestApiProvider::Resource).

## Setup
This gem was not published to RubyGems.org so far, so in your Gemfile use:
```ruby 
gem 'rest_api_provider', git: 'git@github.com:madeinussr/rest_api_provider.git' 
```
``` 
bundle install 
```
then either create a proper config file (in ``` /config/initializers ``` folder if you use Ruby on Rails) or just call that code:
```ruby
RestApiProvider.configure do |config|
  config.api_root = 'https://api.example.com'
  # if you need to include an Authorization header in every request
  config.auth_token = 'Basic XxXxxXxx='
end
```

## Define a Resource
You can define a simple Resource like this:
``` ruby
class TestResource < RestApiProvider::Resource
  set_path '/test_resources/:slug'
  
  # 'application/json' - default
  content_type 'application/x-www-form-urlencoded'

  # include only fields that you want to map to object
  field :slug
  field :title
  field :description
end
```

### Types
You can define an explicit field type and a default value:

``` ruby
class TestResource < RestApiProvider::Resource
  set_path '/test_resources/:slug'

  field :slug
  field :title, String, default: 'Hello World!'
  field :description
end
```

Supported field types:
* String
* Integer
* Fixnum
* Bignum
* Float
* Date
* Array
* Hash

### Slugs and included Resources
Consider _slug_ as an identifier of the particular Resource item.
You can define included Resources like this:

``` ruby
class SubResource < RestApiProvider::Resource
  set_path '/test_resources/:resource_slug/sub_resources/:subresource_slug'

  field :resource_slug
  field :subresource_slug
  field :title
  field :description
end
```

### Validation
There is the list of supported (so far) ActiveRecord-like validations:
* presence
* length
* numericality
* minimum
* maximum
* &block

``` ruby
class TestResource < RestApiProvider::Resource
  set_path '/test_resources/:slug'

  field :slug
  field :number
  field :description

  validates :slug, presence: true
  validates :number, numericality: true
end
```

## Requests
### Default methods
There are some pre-defined request methods (name=>http_verb):
API_METHODS = {all: 'get', grouped: 'get', find: 'get', create: 'post', update: 'put', destroy: 'delete'}
You can use them in this way (slugs are based on a Resource path) 
```ruby
TestResource.find slugs:{slug_1: 'qwe', slug_2: 'rty'}, params: {}, body: {}, headers: {} 
```
* params: {} - url querystring-params
* body: {} - request's body
* headers: {} - request's headers

Default methods has some limitations:
* their target element (response source element) always root
* .all result - Array object
* .grouped result - Hash object
* .find, .create, .update, .destroy result - itself object

### Custom methods
You always can declare your own custom methods ``` http_verb method_name, custom_path ```
``` ruby
class TestResource < RestApiProvider::Resource
  set_path '/test_resources/:slug'

  field :slug
  field :number
  field :description

  get :custom_get, '/some_resource/:some_slug/some_method'
  post :custom_post, '/some_resource/:some_slug/some_method'
  put :custom_put, '/some_resource/:some_slug/some_method'
  delete :custom_delete, '/some_resource/:some_slug/some_method'
end
```

You can specify mapping result's class (Hash or Array, by default - your Resource class itself):
``` ruby
class TestResource < RestApiProvider::Resource
  set_path '/test_resources/:slug'

  field :slug
  field :number

  get :custom_get, '/some_resource/:some_slug/some_method', result: Hash
end
```

You're free to specify data source element path for mapping (by default - root) if your Resource data is not defined in the response's root:
``` ruby
class TestResource < RestApiProvider::Resource
  set_path '/test_resources/:slug'

  field :slug
  field :number

  get :custom_get, '/some_resource/:some_slug/some_method', result: Hash, data_path: '/data/sub_data'
end
```

The same usage:
```ruby
TestResource.custom_get slugs:{some_slug: 'qwe'}, params: {}, body: {}, headers: {}
```

### Paths
```.set_path``` defines the default Resource path. But you always can declare a custom path for a particular method.
``` ruby
class TestResource < RestApiProvider::Resource
  set_path '/test_resources/:slug'

  field :slug
  field :number
  field :description

  get :custom_method, '/some_resource/:some_slug/some_method'
end
```

## Response mapping
This gem awaits that request is a JSON.
Actually, methods .all, .find etc. and custom methods returns a mapped result.
So far you can get a mapping JSON to:
* object
* Array
* Hash