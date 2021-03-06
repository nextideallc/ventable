require 'ventable'

describe Ventable do
  before do
    class TestEvent
      include Ventable::Event
    end
  end

  describe '::enabled?' do
    after { Ventable.enable }

    it 'is true by default' do
      expect(Ventable.enabled?).to be true
    end

    it 'is false after Ventable is disabled' do
      Ventable.disable
      expect(Ventable.enabled?).to be false
    end

    it 'is true after Ventable is re-enabled' do
      Ventable.disable
      Ventable.enable
      expect(Ventable.enabled?).to be true
    end
  end

  describe "including Ventable::Event" do
    it "should create a class instance variable to keep observers" do
      expect(TestEvent.observers).not_to be_nil
      expect(TestEvent.observers.class.name).to eq("Set")
    end

    it "should see observers variable from instance methods" do
      observers = nil
      TestEvent.new.instance_eval do
        observers = self.class.observers
      end
      expect(observers).to_not be_nil
    end

    it "should maintain separate sets of observers for each event" do
      class AnotherEvent
        include Ventable::Event
      end
      expect(AnotherEvent.observers.object_id).to_not eq(TestEvent.observers.object_id)
    end
  end

  describe "#fire" do
    before do
      class TestEvent
        include Ventable::Event
      end
    end

    it "should properly call a Proc observer" do
      run_block = false
      event = nil
      TestEvent.notifies do |e|
        run_block = true
        event = e
      end
      expect(run_block).to eq(false)
      expect(event).to be_nil

      # fire the event
      TestEvent.new.fire!

      expect(run_block).to be true
      expect(event).not_to be_nil
    end

    it "should properly call a class observer" do
      class TestEvent
        class << self
          attr_accessor :flag
        end
        self.flag = "unset"
        def flag= value
          self.class.flag = value
        end
      end

      class TestEventObserver
        def self.handle_test event
          event.flag = "boo"
        end
      end
      TestEvent.notifies TestEventObserver
      expect(TestEvent.flag).to eq("unset")

      TestEvent.new.fire!
      expect(TestEvent.flag).to eq("boo")
    end

    it "should properly call a group of observers" do
      transaction_called = false
      transaction_completed = false
      transaction = ->(observer_block) {
        transaction_called = true
        observer_block.call
        transaction_completed = true
      }

      TestEvent.group :transaction, &transaction
      observer_block_called = false

      # this flag ensures that this block really runs inside
      # the transaction group block
      transaction_already_completed = false
      event_inside = nil
      TestEvent.notifies inside: :transaction do |event|
        observer_block_called = true
        transaction_already_completed = transaction_completed
        event_inside = event
      end

      expect(transaction_called).to be false
      expect(transaction_already_completed).to be false
      expect(observer_block_called).to be false

      TestEvent.new.fire!

      expect(transaction_called).to be  true
      expect(observer_block_called).to be  true
      expect(transaction_called).to be  true
      expect(transaction_already_completed).to be false
      expect(event_inside).to_not be_nil
      expect(event_inside).to be_a(TestEvent)
    end

    context 'when globally disabled' do
      before { Ventable.disable }
      after { Ventable.enable }

      it 'does not notify observers' do
        observers_notified = false

        TestEvent.notifies do |event|
          observers_notified = true
        end

        TestEvent.new.fire!
        expect(observers_notified).to be false
      end
    end
  end

  describe "#default_callback_method" do
    before do
      class SomeAwesomeEvent
        include Ventable::Event
      end

      module Blah
        class AnotherSweetEvent
          include Ventable::Event
        end
      end

      class SomeOtherStuffHappened
        include Ventable::Event
      end
      class ClassWithCustomCallbackMethodEvent
        include Ventable::Event

        def self.ventable_callback_method_name
          :handle_my_special_event
        end
      end
    end

    it "should properly set the callback method name" do
      expect(SomeAwesomeEvent.default_callback_method).to eq(:handle_some_awesome)
      expect(Blah::AnotherSweetEvent.default_callback_method).to eq(:handle_blah__another_sweet)
      expect(SomeOtherStuffHappened.default_callback_method).to eq(:handle_some_other_stuff_happened)
      expect(ClassWithCustomCallbackMethodEvent.default_callback_method).to eq(:handle_my_special_event)
    end
  end

  describe "#configure" do
    it "properly configures the event with observers" do
      notified_observer = false
      TestEvent.configure do
        notifies do
          notified_observer = true
        end
      end
      TestEvent.new.fire!
      expect(notified_observer).to be true
    end

    it "configures observers with groups" do
      notified_observer = false
      called_transaction = false
      TestEvent.configure do
        group :transaction, &->(b){
          b.call
          called_transaction = true
        }
        notifies inside: :transaction do
          notified_observer = true
        end
      end
      TestEvent.new.fire!
      expect(notified_observer).to be true
      expect(called_transaction).to be true
    end

    it "throws exception if :inside references unknown group" do
      begin
        TestEvent.configure do
          notifies inside: :transaction do
            # some stuff
          end
        end
        fail "Shouldn't reach here, must throw a valid exception"
      rescue Exception => e
        expect(e.class).to eq(Ventable::Error)
      end
    end
    it "throws exception if nil observer added to the list" do
      begin
        TestEvent.configure do
          notifies nil
        end
        fail "Shouldn't reach here, must throw a valid exception"
      rescue Exception => e
        expect(e.class).to eq(Ventable::Error)
      end
    end
  end
end
