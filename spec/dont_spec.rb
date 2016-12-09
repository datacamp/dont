require "spec_helper"
require "logger"
require "sqlite3"
require "active_record"

describe Dont do

  before :all do
    @method_calls = []
    Dont.register_handler(:method_logger, -> (object, method) {
      @method_calls << "#{object.class.name}##{method}"
    })
  end

  it "has a version number" do
    expect(Dont::VERSION).not_to be nil
  end

  Car = Class.new do
    include Dont.new(:exception)

    def drive_autopilot
    end

    def drive_manually
    end
    dont_use :drive_manually
  end


  describe ".new(...)" do
    it "fails when used with an unknown handler" do
      expect {
        Class.new { include Dont.new(:deal_with_it) }
      }.to raise_error(
        Dont::MissingHandlerError,
        "Nothing registered with the key :deal_with_it"
      )
    end
  end

  describe "deprecation handling" do
    context "with :exception" do
      it "triggers an exception if the old method is used" do
        expect {
          Car.new.drive_manually
        }.to raise_error(
          Dont::DeprecationError,
          "Don't use `Car#drive_manually`. It's deprecated."
        )
      end
    end
  end

  describe ".register_handler" do
    it "can be used for a custom handler" do
      logger = instance_double(Logger)
      Dont.register_handler(:log_deprecated_call, -> (object, method) {
        logger.warn("Don't use '#{method.to_s}'.")
      })

      klass = Class.new do
        include Dont.new(:log_deprecated_call)

        def shout(msg)
          msg.upcase
        end
        dont_use :shout
      end

      expect(logger).to receive(:warn).with("Don't use 'shout'.")
      result = klass.new.shout("Welcome!")
      expect(result).to eq("WELCOME!")
    end
  end

  describe "ActiveRecord::Base" do
    before(:all) do
      ActiveRecord::Migration.verbose = false
      ActiveRecord::Base.establish_connection(
        adapter: "sqlite3",
        database: ":memory:"
      )
      ActiveRecord::Schema.define(version: 1) do
        create_table :items do |t|
          t.text :name
          t.boolean :usable
        end
      end

      class Item < ActiveRecord::Base
        include Dont.new(:method_logger)
        dont_use :usable
        dont_use :usable?
        dont_use :usable=
      end
    end

    it "still executes the original method correctly" do
      Item.create!(name: "usable", usable: true)
      expect(@method_calls).to eq(["Item#usable="])
      item = Item.last
      expect(item.usable).to eq(true)
      expect(item.usable?).to eq(true)
      expect(@method_calls).to eq(["Item#usable=", "Item#usable", "Item#usable?"])

      item.usable = false
      item.save!
      item.reload
      expect(item.usable).to eq(false)
      expect(item.usable?).to eq(false)

      item.usable = nil
      item.save!
      item.reload
      expect(item.usable).to eq(nil)
      expect(item.usable?).to eq(nil)
    end
  end
end
