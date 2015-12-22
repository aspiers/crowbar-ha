require "spec_helper"

require_relative "../../../../libraries/pacemaker/constraint/location"
require_relative "../../../fixtures/location_constraint"
require_relative "../../../helpers/cib_object"

describe Pacemaker::Constraint::Location do
  let(:fixture) { Chef::RSpec::Pacemaker::Config::LOCATION_CONSTRAINT.dup }
  let(:fixture_definition) {
    Chef::RSpec::Pacemaker::Config::LOCATION_CONSTRAINT_DEFINITION
  }

  def object_type
    "location"
  end

  def pacemaker_object_class
    Pacemaker::Constraint::Location
  end

  def fields
    %w(name rsc score lnode)
  end

  it_should_behave_like "a CIB object"

  describe "#definition_string" do
    it "should return the definition string" do
      expect(fixture.definition_string).to eq(fixture_definition)
    end

    it "should return a short definition string" do
      location = pacemaker_object_class.new("foo")
      location.definition = \
        %!location location1 primitive1 -inf: node1!
      location.parse_definition
      expect(location.definition_string).to eq(<<'EOF'.chomp)
location location1 primitive1 -inf: node1
EOF
    end
  end

  describe "#parse_definition" do
    before(:each) do
      @parsed = pacemaker_object_class.new(fixture.name)
      @parsed.definition = fixture_definition
      @parsed.parse_definition
    end

    it "should parse the rsc" do
      expect(@parsed.rsc).to eq(fixture.rsc)
    end

    it "should parse the score" do
      expect(@parsed.score).to eq(fixture.score)
    end

    it "should parse the node" do
      expect(@parsed.lnode).to eq(fixture.lnode)
    end
  end
end
