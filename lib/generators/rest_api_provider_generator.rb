class RestApiProviderRailtie < Rails::Generators::Base
  source_root(File.expand_path(File.dirname(__FILE__)))

  def copy_initializer
    copy_file 'rest_api_provider.rb', 'config/initializers/rest_api_provider.rb'
  end
end