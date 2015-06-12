require 'spec_helper'

describe RestApiProvider do
  it 'has a version number' do
    expect(RestApiProvider::VERSION).not_to be nil
  end

  describe '#configure' do
    before do
      RestApiProvider.configure do |config|
        config.api_root = 'http://api.example.com'
      end
    end

    it 'returns an example API root path' do
      expect(RestApiProvider.configuration.api_root).to eq('http://api.example.com')
    end

    it 'resets the configuration' do
      RestApiProvider.reset
      config = RestApiProvider.configuration
      expect(config.api_root).to eq('http://')
    end
  end

  describe RestApiProvider::Resource do
    class TestResource < RestApiProvider::Resource
      resource_path '/tests/:slug'

      field :a, type: Integer, default: 1
      field :b, type: String
      field :c

      get :get_tests, '/tests'
    end

    describe 'resource path' do
      it 'has .resource_path' do
        expect(TestResource.respond_to?(:resource_path)).to be_truthy
      end

      it 'assigns path value' do
        expect(TestResource.path).to eq('/tests/:slug')
        class TestResource < RestApiProvider::Resource;
          resource_path '/t/:slug';
        end
        expect(TestResource.path).to eq('/t/:slug')
      end
    end

    describe 'resource methods' do
      context 'with predefined methods' do
        it 'has .all' do
          expect(TestResource.respond_to?(:all)).to be_truthy
        end

        it 'has .grouped' do
          expect(TestResource.respond_to?(:grouped)).to be_truthy
        end

        it 'has .find' do
          expect(TestResource.respond_to?(:find)).to be_truthy
        end

        it 'has .create' do
          expect(TestResource.respond_to?(:create)).to be_truthy
        end

        it 'has .update' do
          expect(TestResource.respond_to?(:update)).to be_truthy
        end

        it 'has .delete' do
          expect(TestResource.respond_to?(:destroy)).to be_truthy
        end
      end

      context 'with custom methods' do
        it 'provides custom method' do
          expect(TestResource.respond_to?(:get_tests)).to be_truthy
        end
      end
    end

    describe 'resource fields' do
      subject(:resource_obj) { TestResource.new }

      context 'with default value' do
        it 'returns default value' do
          expect(resource_obj.a).to eq(1)
        end

        it 'assigns new value' do
          resource_obj.a = 2
          expect(resource_obj.a).to eq(2)
        end
      end

      context 'without default value' do
        it 'returns nil' do
          expect(resource_obj.b).to be_nil
        end

        it 'assigns new value' do
          resource_obj.b = '2'
          expect(resource_obj.b).to eq('2')
        end
      end

      context 'with an explicit type' do
        it 'assigns new value of proper type' do
          resource_obj.b = '2'
          expect(resource_obj.b).to eq('2')
        end

        it 'does not assign new value of unexpected type' do
          resource_obj.a = 'str'
          expect(resource_obj.a).to eq(1)
        end
      end

      context 'with an implicit type' do
        it 'assigns new value of any type' do
          resource_obj.c = {arr: ['123', 123]}
          expect(resource_obj.c).to eq({'arr' => ['123', 123]})
        end
      end
    end
  end

  describe RestApiProvider::Requester do
    subject(:requester) { RestApiProvider::Requester }

    context '.make_request_with' do
      it 'returns an exception if response status != 200' do
        stub_request(:any, /tests/).to_return(status: 500, body: '', headers: {})
        expect { requester.make_request_with path: '/tests' }.to raise_error(RestApiProvider::ApiError)
      end

      it 'returns a body if response status == 200' do
        stub_request(:any, /tests/).to_return(status: 200, body: "{\"message\":\"test\"}", headers: {})
        expect(requester.make_request_with path: '/tests').to eq("{\"message\":\"test\"}")
      end
    end

  end

  describe RestApiProvider::Validation do
    class SimpleValidationExample < RestApiProvider::Resource
      include RestApiProvider::Validation

      field :name
      field :password
      field :code
      field :number, type: Integer

      validates :name, presence: true
      validates :password, length: {within: 6..12}
      validates :code, length: {minimum: 6, maximum: 8}
      validates :number, numericality: true, minimum: 1, maximum: 10
    end

    it 'should be able to register a validation' do
      expect(SimpleValidationExample._validations.size).to eq(4)
    end

    it "should be invalid if a required value isn't present" do
      a = SimpleValidationExample.new
      a.name = nil
      a.valid?
      expect(a.errors[:name].size).to eq(1)
    end

    it 'should be valid if a required value is present' do
      a = SimpleValidationExample.new
      a.name = 'John'
      a.valid?
      expect(a.errors[:name]).to be_empty
    end

    it 'should be invalid if a length within value is outside the range' do
      a = SimpleValidationExample.new(password: '12345')
      a.valid?
      expect(a.errors[:password].size).to eq(1)
    end

    it 'should be valid if a length within value is inside the range' do
      a = SimpleValidationExample.new(password: '123456')
      a.valid?
      expect(a.errors[:password].size).to eq(0)
    end

    it 'should be invalid if a length is below the minimum' do
      a = SimpleValidationExample.new(code: '12345')
      a.valid?
      expect(a.errors[:code].size).to eq(1)
    end

    it 'should be valid if a length is above or equal to the minimum and below the maximum' do
      a = SimpleValidationExample.new(code: '123456')
      a.valid?
      expect(a.errors[:code].size).to eq(0)
    end

    it 'should be invalid if a length is above the maximum' do
      a = SimpleValidationExample.new(code: '123456789')
      a.valid?
      expect(a.errors[:code].size).to eq(1)
    end

    it 'should be able to validate that a field is numeric' do
      a = SimpleValidationExample.new(number: 'Bob')
      a.valid?
      expect(a.errors[:number].size).to be > 0
    end

    it 'should be able to validate that a numeric field is above or equal to a minimum' do
      a = SimpleValidationExample.new(number: 0)
      a.valid?
      expect(a.errors[:number].size).to be > 0
    end

    it 'should be able to validate that a numeric field is above or equal to a minimum' do
      a = SimpleValidationExample.new(number: 50)
      a.valid?
      expect(a.errors[:number].size).to be > 0
    end

    it 'should be invalid when a block adds an error' do
      class ValidationExample1 < RestApiProvider::Resource
        include RestApiProvider::Validation

        field :name

        validates :name do |object, name, value|
          object.errors[name] << 'must be over 4 chars long' if value.length <= 4
        end
      end
      a = ValidationExample1.new
      a.name = 'John'
      a.valid?
      expect(a.errors[:name].size).to eq(1)
    end

    it "should be valid when a block doesn't add an error" do
      class ValidationExample2 < RestApiProvider::Resource
        include RestApiProvider::Validation

        field :name

        validates :name do |object, name, value|
          object.errors[name] << 'must be over 4 chars long' if value.length <= 4
        end
      end
      a = ValidationExample2.new
      a.name = 'Johny'
      a.valid?
      expect(a.errors[:name]).to be_empty
    end
  end

  describe RestApiProvider::JsonMapper do
    subject(:mapper) { RestApiProvider::JsonMapper }
    class TestModel < RestApiProvider::Resource
      field :a, type: Integer, default: 1
      field :b, type: String
    end
    let(:model) { TestModel.new }

    context '.map2object with object' do
      it 'creates object with proper fields' do
        obj = mapper.map2object("{\"a\":\"2\",\"b\":\"str\"}" , TestModel)
        expect(obj.a).to eq(2)
        expect(obj.b).to eq('str')
      end

      it 'updates model field with proper type' do
        mapper.map2object("{\"a\":\"2\",\"b\":\"str\"}" , model)
        expect(model.a).to eq(2)
        expect(model.b).to eq('str')
      end

      it 'does not update model field with unexpected type' do
        mapper.map2object("{\"a\":\"str\",\"b\":\"1\"}", model)
        expect(model.a).to eq(1)
        expect(model.b).to eq('1')
      end

      it 'does not update model with unexpected field' do
        mapper.map2object("{\"a\":\"2\",\"b\":\"1\",\"c\":\"str\"}", model)
        expect(model.a).to eq(2)
        expect(model.b).to eq('1')
        expect(model.c).to be_nil
      end

      it 'maps Array type implicitly' do
        class TestModel < RestApiProvider::Resource
          field :a
          field :b, type: String
        end
        obj = mapper.map2object("{\"a\":[1,\"2\",3,\"4\"],\"b\":2}" , TestModel)
        expect(obj.a).to eq([1,'2',3,'4'])
        expect(obj.b).to eq('2')
      end

      it 'maps Array type explicitly' do
        class TestModel < RestApiProvider::Resource
          field :a, type: Array
          field :b, type: String
        end
        obj = mapper.map2object("{\"a\":[1,\"2\",3,\"4\"],\"b\":\"str\"}" , TestModel)
        expect(obj.a).to eq([1,'2',3,'4'])
        expect(obj.b).to eq('str')
      end

      it 'maps Hash type implicitly' do
        class TestModel < RestApiProvider::Resource
          field :a
        end
        obj = mapper.map2object("{\"a\":{\"aa\":\"2\",\"bb\":\"4\"}}" , TestModel)
        expect(obj.a).to eq({'aa'=>'2','bb'=>'4'})
      end

      it 'maps Hash type explicitly' do
        class TestModel < RestApiProvider::Resource
          field :a, type: Hash
        end
        obj = mapper.map2object("{\"a\":{\"aa\":\"2\",\"bb\":\"4\"}}" , TestModel)
        expect(obj.a).to eq({'aa'=>'2','bb'=>'4'})
      end

      it '.map2object works by path' do
        class TestModel < RestApiProvider::Resource
          field :a
        end
        path_elements = ['a','aa','e']
        obj = mapper.map2object("{\"a\":{\"aa\":{\"c\":\"d\",\"e\":{\"a\":\"g\"}},\"bb\":\"4\"}}" , TestModel, path_elements)
        expect(obj.a).to eq('g')
      end

      it '.map2array works by path' do
        class TestModel < RestApiProvider::Resource
          field :a, type: Array
        end
        path_elements = ['a','aa','e']
        arr = mapper.map2array("{\"a\":{\"aa\":{\"c\":\"d\",\"e\":[{\"a\":[1,\"2\",3]}]},\"bb\":\"4\"}}" , TestModel, path_elements)
        expect(arr.first.a).to eq([1,'2',3])
      end

      it '.map2hash works by path' do
        class TestModel < RestApiProvider::Resource
          field :a, type: Hash
        end
        path_elements = ['a','aa','e']
        obj = mapper.map2hash("{\"a\":{\"aa\":{\"c\":\"d\",\"e\":{\"group1\":[{\"a\":[1,\"2\",3]}]}},\"bb\":\"4\"}}" , TestModel, path_elements)
        expect(obj['group1'].first.a).to eq([1,'2',3])
      end
    end
  end
end
