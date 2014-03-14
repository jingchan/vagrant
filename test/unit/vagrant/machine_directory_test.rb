require "json"
require "pathname"
require "tempfile"

require File.expand_path("../../base", __FILE__)

require "vagrant/machine_index"

describe Vagrant::MachineIndex do
  include_context "unit"

  let(:data_dir) { temporary_dir }

  subject { described_class.new(data_dir) }

  it "raises an exception if the data file is corrupt" do
    data_dir.join("index").open("w") do |f|
      f.write(JSON.dump({}))
    end

    expect { subject }.
      to raise_error(Vagrant::Errors::CorruptMachineIndex)
  end

  it "raises an exception if the JSON is invalid" do
    data_dir.join("index").open("w") do |f|
      f.write("foo")
    end

    expect { subject }.
      to raise_error(Vagrant::Errors::CorruptMachineIndex)
  end

  describe "#get and #release" do
    before do
      data = {
        "version" => 1,
        "machines" => {
          "bar" => {
            "name" => "default",
            "provider" => "vmware",
            "vagrantfile_path" => "/foo/bar/baz",
            "state" => "running",
            "updated_at" => "foo",
          }
        }
      }

      data_dir.join("index").open("w") do |f|
        f.write(JSON.dump(data))
      end
    end

    it "returns nil if the machine doesn't exist" do
      expect(subject.get("foo")).to be_nil
    end

    it "returns a valid entry if the machine exists" do
      result = subject.get("bar")

      expect(result.id).to eq("bar")
      expect(result.name).to eq("default")
      expect(result.provider).to eq("vmware")
      expect(result.vagrantfile_path).to eq(Pathname.new("/foo/bar/baz"))
      expect(result.state).to eq("running")
      expect(result.updated_at).to eq("foo")
    end

    it "locks the entry so subsequent gets fail" do
      result = subject.get("bar")
      expect(result).to_not be_nil

      expect { subject.get("bar") }.
        to raise_error(Vagrant::Errors::MachineLocked)
    end

    it "can unlock a machine" do
      result = subject.get("bar")
      expect(result).to_not be_nil
      subject.release(result)

      result = subject.get("bar")
      expect(result).to_not be_nil
    end
  end

  describe "#set and #get and #delete" do
    let(:entry_klass) { Vagrant::MachineIndex::Entry }

    let(:new_entry) do
      entry_klass.new.tap do |e|
        e.name = "foo"
        e.vagrantfile_path = "/bar"
      end
    end

    it "adds a new entry" do
      result = subject.set(new_entry)
      expect(result.id).to_not be_empty

      # It should be locked
      expect { subject.get(result.id) }.
        to raise_error(Vagrant::Errors::MachineLocked)

      # Get it froma new class and check the results
      subject.release(result)
      subject = described_class.new(data_dir)
      entry   = subject.get(result.id)
      expect(entry).to_not be_nil
      expect(entry.name).to eq("foo")

      # TODO: test that updated_at is set
    end

    it "can delete an entry" do
      result = subject.set(new_entry)
      expect(result.id).to_not be_empty
      subject.delete(result)

      # Get it from a new class and check the results
      subject = described_class.new(data_dir)
      entry   = subject.get(result.id)
      expect(entry).to be_nil
    end

    it "can delete an entry that doesn't exist" do
      e = entry_klass.new
      expect(subject.delete(e)).to be_true
    end

    it "updates an existing entry" do
      entry = entry_klass.new
      entry.name = "foo"
      entry.vagrantfile_path = "/bar"

      result = subject.set(entry)
      expect(result.id).to_not be_empty

      result.name = "bar"

      nextresult = subject.set(result)
      expect(nextresult.id).to eq(result.id)

      # Release it so we can test the contents
      subject.release(nextresult)

      # Get it froma new class and check the results
      subject = described_class.new(data_dir)
      entry   = subject.get(result.id)
      expect(entry).to_not be_nil
      expect(entry.name).to eq("bar")
    end
  end
end
