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
      field :a, type: Integer, default: 1
      field :b, type: String
      field :c

      get :get_tests, '/tests'
      get :custom_result, result: Hash
      get :custom_data_path, data_path: '/a/c/d'
    end

    class HavingOneResource < RestApiProvider::Resource
      has_one :test_resource, rel: 'test:resource'
    end

    class HavingManyResource < RestApiProvider::Resource
      has_many :test_resources, rel: 'test:resources'
    end

    class HavingManyWithDataPathResource < RestApiProvider::Resource
      has_many :test_resources, rel: 'test:resources', data_path: '/data'
    end

    class BelongingResource < RestApiProvider::Resource
      belongs_to :test_resource, rel: 'test:resource'
    end

    describe 'relations' do
      it 'has .belongs_to' do
        expect(TestResource.respond_to?(:belongs_to)).to be_truthy
      end

      it 'has .has_one' do
        expect(TestResource.respond_to?(:has_one)).to be_truthy
      end

      it 'has .has_many' do
        expect(TestResource.respond_to?(:has_many)).to be_truthy
      end

      describe 'relations storing' do
        subject {BelongingResource.relations}

        it 'stores relations as hashes' do
          is_expected.to_not be_nil
          is_expected.to be_a Hash
        end

        it 'stores relation name as hash key' do
          is_expected.to have_key('TestResource')
        end

        it 'stores relation details as a hash with keys :type & :rel' do
          expect(subject['TestResource']).to be_a Hash
          expect(subject['TestResource']).to have_key(:type)
          expect(subject['TestResource']).to have_key(:rel)
          expect(subject['TestResource']).to have_key(:data_path)
        end

        it 'defines a default rel as provided resource name' do
          class SomeResource < RestApiProvider::Resource
            belongs_to :test_resource
          end

          expect(SomeResource.relations).not_to be_nil
          expect(SomeResource.relations['TestResource']).to have_key(:rel)
          expect(SomeResource.relations['TestResource'][:rel]).to eq('test_resource')
        end
      end

      describe '.has_one' do
        subject {HavingOneResource.relations}

        it 'assigns relation name as a singular form of related resource class name' do
          expect(subject.keys.first).to eq('TestResource')
        end

        it 'stores type as :one2one' do
          expect(subject['TestResource'][:type]).to eq(:one2one)
        end

        it 'stores proper :rel' do
          expect(subject['TestResource'][:rel]).to eq('test:resource')
        end
      end

      describe '.has_many' do
        subject {HavingManyResource.relations}

        it 'assigns relation name as a singular form of related resource class name' do
          expect(subject.keys.first).to eq('TestResource')
        end

        it 'stores type as :one2many' do
          expect(subject['TestResource'][:type]).to eq(:one2many)
        end

        it 'stores proper :rel' do
          expect(subject['TestResource'][:rel]).to eq('test:resources')
        end
      end

      describe '.belongs_to' do
        subject {BelongingResource.relations}
        let(:relation){subject['TestResource']}

        it 'assigns relation name as singular form of related resource class name' do
          expect(subject.keys.first).to eq('TestResource')
        end

        it 'stores type as :one2one' do
          expect(subject['TestResource'][:type]).to eq(:one2one)
        end

        it 'stores proper :rel' do
          expect(relation[:rel]).to eq('test:resource')
        end
      end

      describe 'querying' do
        let(:test_resource) do
          TestResource.new.tap do |t|
            t.a = 2
            t.b = '3'
            t.c = ['4']
          end
        end
        let(:response){RestApiProvider::ApiResponse.new(status: 200, headers: {}, body: test_resource.attributes.to_json)}

        describe 'with .belongs_to relation' do
          let(:belonger){BelongingResource.new.tap {|t| t.links = {'test:resource' =>{'href' => 'https://test.com/test_resources'}}}}

          it 'returns related object' do
            allow(RestApiProvider::Requester).to receive(:make_request_with).and_return(response)
            expect(belonger.test_resource).not_to be_nil
            expect(belonger.test_resource.a).to eq 2
            expect(belonger.test_resource.b).to eq '3'
            expect(belonger.test_resource.c).to eq ['4']
          end
        end

        describe 'with .has_one relation' do
          let(:haver){HavingOneResource.new.tap {|t| t.links = {'test:resource' =>{'href' => 'https://test.com/test_resources'}}}}

          it 'returns related object' do
            allow(RestApiProvider::Requester).to receive(:make_request_with).and_return(response)
            expect(haver.test_resource).not_to be_nil
            expect(haver.test_resource.a).to eq 2
            expect(haver.test_resource.b).to eq '3'
            expect(haver.test_resource.c).to eq ['4']
          end
        end

        describe 'with .has_many relation' do
          let(:response){RestApiProvider::ApiResponse.new(status: 200, headers: {}, body: [test_resource.attributes, test_resource.attributes].to_json)}
          let(:haver){HavingManyResource.new.tap {|t| t.links = {'test:resources' =>{'href' => 'https://test.com/test_resources'}}}}

          it 'returns related object' do
            allow(RestApiProvider::Requester).to receive(:make_request_with).and_return(response)
            expect(haver.test_resources).not_to be_nil
            expect(haver.test_resources).is_a? Array
            expect(haver.test_resources.length).to eq 2
            expect(haver.test_resources.first.a).to eq 2
            expect(haver.test_resources.first.b).to eq '3'
            expect(haver.test_resources.first.c).to eq ['4']
          end
        end

        describe 'with data_path specified' do
          let(:response){RestApiProvider::ApiResponse.new(status: 200, headers: {}, body: {data: [test_resource.attributes, test_resource.attributes]}.to_json)}
          let(:haver){HavingManyWithDataPathResource.new.tap {|t| t.links = {'test:resources' =>{'href' => 'https://test.com/test_resources'}}}}

          it 'returns related object' do
            allow(RestApiProvider::Requester).to receive(:make_request_with).and_return(response)
            expect(haver.test_resources).not_to be_nil
            expect(haver.test_resources).is_a? Array
            expect(haver.test_resources.length).to eq 2
            expect(haver.test_resources.first.a).to eq 2
            expect(haver.test_resources.first.b).to eq '3'
            expect(haver.test_resources.first.c).to eq ['4']
          end
        end
      end
    end

    describe 'resource path' do
      it 'has .resource_path' do
        expect(TestResource.respond_to?(:resource_path)).to be_truthy
      end

      it 'has default value as /resources/:slug' do
        expect(TestResource.path).to eq('/test_resources/:slug')
      end

      it 'assigns path value' do
        class TestResource < RestApiProvider::Resource
          resource_path '/t/:slug'
        end
        expect(TestResource.path).to eq('/t/:slug')
      end
    end

    describe 'content type' do
      it 'has .resource_path' do
        expect(TestResource.respond_to?(:content_type)).to be_truthy
      end

      it 'has default value' do
        expect(TestResource.content).to eq('application/json')
      end

      it 'assigns path value' do
        class TestResource < RestApiProvider::Resource
          content_type 'application/x-www-form-urlencoded';
        end
        expect(TestResource.content).to eq('application/x-www-form-urlencoded')
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
        it 'supports custom method' do
          expect(TestResource.respond_to?(:get_tests)).to be_truthy
        end

        it 'supports result class definition' do
          response = RestApiProvider::ApiResponse.new(status: 200, headers: {}, body: {g1: [{a: 1, b: 2, c: 3}, {a: 4, b: 5, c: 6}], g2: [{a: 7, b: 8, c: 9}]}.to_json)
          allow(RestApiProvider::Requester).to receive(:make_request_with).and_return(response)
          expect(TestResource.custom_result['g1'][0].a).to eq(1)
          expect(TestResource.custom_result['g1'][0].b).to eq('2')
          expect(TestResource.custom_result['g1'][0].c).to eq(3)
          expect(TestResource.custom_result['g1'][1].a).to eq(4)
          expect(TestResource.custom_result['g1'][1].b).to eq('5')
          expect(TestResource.custom_result['g1'][1].c).to eq(6)
          expect(TestResource.custom_result['g2'][0].a).to eq(7)
          expect(TestResource.custom_result['g2'][0].b).to eq('8')
          expect(TestResource.custom_result['g2'][0].c).to eq(9)
        end

        it 'supports data path' do
          response = RestApiProvider::ApiResponse.new(status: 200, headers: {}, body: {a: {c: {d: {a: 2, b: 3, c: 4}}}, b: {a: 1}}.to_json)
          allow(RestApiProvider::Requester).to receive(:make_request_with).and_return(response)
          expect(TestResource.custom_data_path.a).to eql(2)
          expect(TestResource.custom_data_path.b).to eql('3')
          expect(TestResource.custom_data_path.c).to eql(4)
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
      it 'returns a response hash if response status is between 100 and 400 codes' do
        stub_request(:any, /tests/).to_return(status: 200, headers: {}, body: "{\"message\":\"test\"}")
        response = RestApiProvider::ApiResponse.new(status: 200, headers: {}, body: "{\"message\":\"test\"}")
        expect(requester.make_request_with(path: '/tests').status).to eq(response.status)
        expect(requester.make_request_with(path: '/tests').headers).to eq(response.headers)
        expect(requester.make_request_with(path: '/tests').body).to eq(response.body)
      end

      it 'returns an exception if response status is NOT between 100 and 400 codes' do
        stub_request(:any, /tests/).to_return(status: 500, body: '', headers: {})
        expect { requester.make_request_with path: '/tests' }.to raise_error(RestApiProvider::ApiError)
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

    it 'should be invalid if a required value is a blank string' do
      a = SimpleValidationExample.new
      a.name = ''
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

  describe RestApiProvider::Mapper do
    subject(:mapper) { RestApiProvider::Mapper }
    class TestModel < RestApiProvider::Resource
      field :a, type: Integer, default: 1
      field :b, type: String
    end
    let(:model) { TestModel.new }
    let(:response) { RestApiProvider::ApiResponse.new(status: 200, headers: {}, body: {a: 2, b: 'str'}.to_json) }

    context '.map2object' do
      it 'creates object with proper fields' do
        obj = mapper.map2object(response, TestModel)
        expect(obj.a).to eq(2)
        expect(obj.b).to eq('str')
      end

      it 'updates model field with proper type' do
        mapper.map2object(response, model)
        expect(model.a).to eq(2)
        expect(model.b).to eq('str')
      end

      it 'does not update model field with unexpected type' do
        response = RestApiProvider::ApiResponse.new(status: 200, headers: {}, body: {a: 'str', b: 1}.to_json)
        mapper.map2object(response, model)
        expect(model.a).to eq(1)
        expect(model.b).to eq('1')
      end

      it 'does not update model with unexpected field' do
        response = RestApiProvider::ApiResponse.new(status: 200, headers: {}, body: {a: 2, b: 1, c: 'str'}.to_json)
        mapper.map2object(response, model)
        expect(model.a).to eq(2)
        expect(model.b).to eq('1')
        expect(model.c).to be_nil
      end

      it 'maps Array type implicitly' do
        class TestModel < RestApiProvider::Resource
          field :a
          field :b, type: String
        end
        response = RestApiProvider::ApiResponse.new(status: 200, headers: {}, body: {a: [1, '2', 3, '4'], b: 2}.to_json)
        obj = mapper.map2object(response, TestModel)
        expect(obj.a).to eq([1, '2', 3, '4'])
        expect(obj.b).to eq('2')
      end

      it 'maps Array type explicitly' do
        class TestModel < RestApiProvider::Resource
          field :a, type: Array
          field :b, type: String
        end
        response = RestApiProvider::ApiResponse.new(status: 200, headers: {}, body: {a: [1, '2', 3, '4'], b: 'str'}.to_json)
        obj = mapper.map2object(response, TestModel)
        expect(obj.a).to eq([1, '2', 3, '4'])
        expect(obj.b).to eq('str')
      end

      it 'maps Hash type implicitly' do
        class TestModel < RestApiProvider::Resource
          field :a
        end
        response = RestApiProvider::ApiResponse.new(status: 200, headers: {}, body: {a: {aa: 2, bb: 4}}.to_json)
        obj = mapper.map2object(response, TestModel)
        expect(obj.a).to eq({'aa' => 2, 'bb' => 4})
      end

      it 'maps Hash type explicitly' do
        class TestModel < RestApiProvider::Resource
          field :a, type: Hash
        end
        response = RestApiProvider::ApiResponse.new(status: 200, headers: {}, body: {a: {aa: 2, bb: 4}}.to_json)
        obj = mapper.map2object(response, TestModel)
        expect(obj.a).to eq({'aa' => 2, 'bb' => 4})
      end

      it 'works by explicit element path' do
        class TestModel < RestApiProvider::Resource
          field :a
        end
        path_elements = %w(a aa d)
        response = RestApiProvider::ApiResponse.new(status: 200, headers: {}, body: {a: {aa: {c: 1, d: {a: 2}}, bb: 0}}.to_json)
        obj = mapper.map2object(response, TestModel, path_elements)
        expect(obj.a).to eq(2)
      end

      it 'provides ApiResponse object if response body is blank' do
        response = RestApiProvider::ApiResponse.new(status: 201, headers: {'some_header'=>'header value'}, body: '')
        result = mapper.map2object(response, TestModel)
        expect(result).not_to be_nil
        expect(result.status).to eq(201)
        expect(result.headers['some_header']).to eq('header value')
      end

    end

    context '.map2array' do
      it 'calls .map2object' do
        response = RestApiProvider::ApiResponse.new(status: 200, headers: {}, body: [{a: 2, b: 'str'}, {a: 3, b: 's'}].to_json)
        expect(mapper).to receive(:map2object).exactly(2).times
        mapper.map2array(response, TestModel)
      end

      it 'creates an array of objects' do
        response = RestApiProvider::ApiResponse.new(status: 200, headers: {}, body: [{a: 2, b: 'str'}, {a: 3, b: 's'}].to_json)
        result = mapper.map2array(response, TestModel)
        expect(result).to be_an_instance_of Array
        expect(result.length).to eq(2)
      end

      it 'works by explicit element path' do
        class TestModel < RestApiProvider::Resource
          field :a
        end
        path_elements = %w(a aa d)
        response = RestApiProvider::ApiResponse.new(status: 200, headers: {}, body: {a: {aa: {c: 1, d: [{a: 2}, {a: 3}]}, bb: 0}}.to_json)
        arr = mapper.map2array(response, TestModel, path_elements)
        expect(arr[0].a).to eq(2)
        expect(arr[1].a).to eq(3)
      end

      it 'provides ApiResponse object if response body is blank' do
        response = RestApiProvider::ApiResponse.new(status: 201, headers: {'some_header'=>'header value'}, body: '')
        result = mapper.map2array(response, TestModel)
        expect(result).not_to be_nil
        expect(result.status).to eq(201)
        expect(result.headers['some_header']).to eq('header value')
      end
    end

    context '.map2hash' do
      it 'calls .map2object' do
        response = RestApiProvider::ApiResponse.new(status: 200, headers: {}, body: {group: [{a: 2, b: 'str'}, {a: 3, b: 's'}]}.to_json)
        expect(mapper).to receive(:map2object).at_least(:once)
        mapper.map2hash(response, TestModel)
      end

      it 'creates a group of objects' do
        response = RestApiProvider::ApiResponse.new(status: 200, headers: {}, body: {group: [{a: 2, b: 'str'}, {a: 3, b: 's'}]}.to_json)
        result = mapper.map2hash(response, TestModel)
        expect(result).to be_an_instance_of Hash
        expect(result.keys.first).to eq('group')
        expect(result['group']).to be_an_instance_of Array
        expect(result['group'].first).to be_an_instance_of TestModel
        expect(result['group'].first.a).to eq(2)
      end

      it 'works by explicit element path' do
        class TestModel < RestApiProvider::Resource
          field :a
        end
        path_elements = %w(a aa d)
        response = RestApiProvider::ApiResponse.new(status: 200, headers: {}, body: {a: {aa: {c: 1, d: {g1: [{a: 2}, {a: 3}], g2: [{a: 4}, {a: 5}]}}, bb: 0}}.to_json)
        obj = mapper.map2hash(response, TestModel, path_elements)
        expect(obj['g1'][0].a).to eq(2)
        expect(obj['g1'][1].a).to eq(3)
        expect(obj['g2'][0].a).to eq(4)
        expect(obj['g2'][1].a).to eq(5)
      end

      it 'provides ApiResponse object if response body is blank' do
        response = RestApiProvider::ApiResponse.new(status: 201, headers: {'some_header'=>'header value'}, body: '')
        result = mapper.map2hash(response, TestModel)
        expect(result).not_to be_nil
        expect(result.status).to eq(201)
        expect(result.headers['some_header']).to eq('header value')
      end
    end
  end
end
