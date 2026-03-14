require 'spec_helper'
require 'gb_paperclip/paperclip/attachment'

unless defined? TestException
  class TestException < Exception;
  end
end

describe Paperclip::Attachment do

  before(:each) do
    @file = File.new(fixture_file('5k.png'), 'rb')
    @file.binmode
    rebuild_model storage: :fake
    @dummy        = Dummy.create!
    @dummy.avatar = @file
    @attachment   = @dummy.avatar
  end

  context 'saving with lock' do
    it 'should put save lock while saving' do
      async_flag                          = false
      @attachment.queued_for_write[:test] = Paperclip.io_adapters.for(@file)
      GBDispatch.dispatch_async(:test) do
        @attachment.with_save_lock do
          sleep(0.3)
          async_flag = true
        end
      end
      sleep(0.1)
      GBDispatch.dispatch_sync(:save) do
        @dummy.save
      end
      expect(async_flag).to eq true
      wait_for :test
    end

    it 'should use status lock' do
      async_flag                          = false
      @attachment.queued_for_write[:test] = Paperclip.io_adapters.for(@file)
      GBDispatch.dispatch_async(:test) do
        @attachment.send(:status_lock).lock
        sleep(0.3)
        async_flag = true
        @attachment.send(:status_lock).unlock
      end
      sleep(0.1)
      GBDispatch.dispatch_sync :save do
        sleep(0.05)
        @attachment.save
      end
      expect(async_flag).to eq true
    end
  end

  it 'unlink files should handle nil values' do
    file = File.new(fixture_file('5k.png'), 'rb')
    expect { @attachment.unlink_files([file, nil]) }.not_to raise_error
    expect(file.closed?).to be_truthy
  end

  context 'processing info' do
    context 'processing' do
      it 'should add style name to processor tracker' do
        @attachment.processing(:test_style)
        expect(@attachment.instance_variable_get :@processor_tracker).to include :test_style
      end

      it 'should add style name to processor tracker when style passed' do
        @attachment.processing(Paperclip::Style.new(:test_style, '143x143#', @attachment))
        expect(@attachment.instance_variable_get :@processor_tracker).to include :test_style
      end

      it 'should set processed styles as empty array on instance' do
        @attachment.processing(:test_style)
        expect(@dummy.processed_styles).to be_a Array
      end

      context 'set processing as true' do
        it 'for new model' do
          dummy        = Dummy.new
          dummy.avatar = @file
          dummy.avatar.processing(:test_style)
          expect(dummy.processing).to eq true
          expect(dummy.new_record?).to be_truthy
        end

        it 'for dirty model' do
          @attachment.send :dirty!
          @attachment.processing(:test_style)
          expect(@dummy.processing).to eq true
          expect(@dummy.changes.keys).to include 'processing'
        end

        it 'for saved model' do
          @dummy.save!
          expect(@attachment.dirty?).to be_falsey
          @attachment.processing(:test_style)
          expect(@dummy.processing).to eq true
          expect(@dummy.changes.keys).not_to include 'processing'
        end

        it 'should save if saving on different thread' do
          unless  defined? SleepyDummy
            class SleepyDummy < Dummy
              self.table_name = 'dummies'
              after_save :take_nap

              def take_nap
                sleep(rand)
              end
            end
          end
          dummy = nil
          GBDispatch.dispatch_sync(:save) do
            dummy        = SleepyDummy.new
            dummy.avatar = @file
          end
          GBDispatch.dispatch_async(:save) do
            dummy.save!
          end
          GBDispatch.dispatch_sync(:process) do
            sleep(0.1)
            expect { dummy.avatar.processing(:test_style) }.not_to raise_error
          end
          wait_for :save
          expect(dummy.avatar.saved[:original]).not_to be_nil
          expect(dummy.changes.keys.any?).to be_falsey
          expect(dummy.reload.processing).to eq true
        end
      end
    end

    it 'ensure_is_created should timeout' do
      flag   = false
      thread = Thread.new do
        begin
          @attachment.send :ensure_is_created, 0.02 do
            raise ActiveRecord::RecordNotFound
          end
        rescue ActiveRecord::RecordNotFound
          flag = true
        end
      end
      thread.join(0.08)
      expect(thread.alive?).to be_falsey
      expect(flag).to eq true
    end

    context 'saving processing info' do
      it 'should use save lock' do
        async_flag = false
        @attachment.instance_variable_set :@processed_styles, [:foo, :bar]
        GBDispatch.dispatch_async(:test) do
          @attachment.with_save_lock do
            sleep(0.3)
            async_flag = true
          end
        end
        GBDispatch.dispatch_sync :save do
          sleep 0.1
          @attachment.send :save_processing_info
        end
        expect(async_flag).to eq true
        wait_for :test
      end

      it 'should set proper value for new object' do
        dummy = Dummy.new
        dummy.avatar.instance_variable_set :@processed_styles, [:foo, :bar]
        dummy.avatar.send :save_processing_info
        expect(dummy.processing).to eq false
        expect(dummy.processed_styles).to eq [:foo, :bar]
        expect(dummy.new_record?).to be_truthy
      end

      it 'should set proper value for dirty object' do
        @dummy.processing = true
        @dummy.save!
        @attachment.send :dirty!
        @attachment.instance_variable_set :@processed_styles, [:foo, :bar]
        @attachment.send :save_processing_info
        expect(@dummy.processing).to eq false
        expect(@dummy.processed_styles).to eq [:foo, :bar]
        expect(@dummy.changes).to include 'processed_styles', 'processing'
      end

      it 'should save proper values for saved objects' do
        @dummy.processing = true
        @dummy.save!
        @attachment.instance_variable_set :@processed_styles, [:foo, :bar]
        @attachment.send :save_processing_info
        expect(@dummy.changes).not_to include 'processed_styles', 'processing'
        expect(@dummy.reload.processing).to eq false
        expect(@dummy.processed_styles).to eq [:foo, :bar]
      end

      100.times do |counter|
        it "should save if saving on different thread #{counter}" do
          unless defined? SleepyDummy
            class SleepyDummy < Dummy
              self.table_name = 'dummies'
              after_save :take_nap

              def take_nap
                sleep(rand)
              end
            end
          end
          dummy  = nil
          status = nil
          GBDispatch.dispatch_sync(:save) do
            dummy        = SleepyDummy.new
            dummy.avatar = @file
          end
          GBDispatch.dispatch_async(:save) do
            Dummy.transaction do
              status = dummy.save!
            end
          end
          GBDispatch.dispatch_sync(:process) do
            sleep(0.1)
            dummy.avatar.instance_variable_set :@processed_styles, [:foo, :bar]
            expect { dummy.avatar.send :save_processing_info }.not_to raise_error
          end
          wait_for :save
          expect(dummy.avatar.saved[:original]).not_to be_nil
          expect(status).to be_truthy
          if dummy.changes.keys.any?
            puts dummy.changes
          end
          expect(dummy.changes.keys).to eq []
          expect(dummy.reload.processing).to eq false
          expect(dummy.processed_styles).to eq [:foo, :bar]
        end
      end
    end

    context 'set processing info' do
      it 'should handle failed processing styles' do
        @attachment.processing(:fail_test)
        @attachment.processing(:other)
        @attachment.failed_processing(:fail_test)
        expect(@attachment.instance_variable_get :@processor_tracker).not_to include :fail_test
        expect(@attachment.instance_variable_get :@processor_tracker).to include :other
      end

      it 'should handle failed processing styles called few times' do
        @attachment.processing(:fail_test)
        @attachment.processing(:other)
        (rand(4)+2).times { @attachment.failed_processing(:fail_test) }
        expect(@attachment.instance_variable_get :@processor_tracker).not_to include :fail_test
        expect(@attachment.instance_variable_get :@processor_tracker).to include :other
      end

      it 'should handle finished style' do
        @attachment.processing(:processed)
        @attachment.processing(:other)
        @attachment.finished_processing :processed
        expect(@attachment.instance_variable_get :@processor_tracker).not_to include :processed
        expect(@attachment.instance_variable_get :@processed_styles).to include :processed
        expect(@attachment.instance_variable_get :@processor_tracker).to include :other
      end

      it 'should handle finished style called few times' do
        @attachment.processing(:processed)
        @attachment.processing(:other)
        (rand(4)+2).times { @attachment.finished_processing :processed }
        expect(@attachment.instance_variable_get :@processor_tracker).not_to include :processed
        expect(@attachment.instance_variable_get :@processed_styles).to include :processed
        expect(@attachment.instance_variable_get :@processor_tracker).to include :other
      end

      it 'should handle all process' do
        @dummy.save!
        @attachment.processing(:processed)
        @attachment.processing(:fail_test)
        @attachment.failed_processing(:fail_test)
        @attachment.finished_processing :processed
        @dummy.reload
        expect(@dummy.processing).to eq false
        expect(@dummy.processed_styles).to eq [:processed]
      end
    end
  end

  context 'post process style' do
    before(:each) do
      rebuild_model storage: :fake, styles: { thumb: '50x50#' }, processors: [:fake_processor]
      @dummy        = Dummy.create!
      @dummy.avatar = @file
      @attachment   = @dummy.avatar
      @style        = @attachment.styles[:thumb]
    end

    it 'should call processing method' do
      expect(@attachment).to receive(:processing).with(@style)
      @attachment.post_process_style(:thumb, @style)
      expect(@attachment.queued_for_write[:thumb]).to be
    end

    it 'should handle nil processor result' do
      Paperclip::FakeProcessor.return_nil = true
      @attachment.post_process_style(:thumb, @style)
      expect(@attachment.queued_for_write.keys).not_to include :thumb
      Paperclip::FakeProcessor.return_nil = false
    end

    context 'should call failed processing style on error' do
      it 'Paperclip::Errors::NotIdentifiedByImageMagickError' do
        Paperclip::FakeProcessor.raise_error = Paperclip::Errors::NotIdentifiedByImageMagickError.new 'test'
        expect(@attachment).to receive(:failed_processing).with(@style)
        @attachment.post_process_style(:thumb, @style)
        Paperclip::FakeProcessor.raise_error = false
      end

      it 'any error' do
        Paperclip::FakeProcessor.raise_error = 'test error'
        expect(@attachment).to receive(:failed_processing).with(@style)
        expect { @attachment.post_process_style(:thumb, @style) }.to raise_error(RuntimeError)
        Paperclip::FakeProcessor.raise_error = nil
      end
    end
  end

  context 'locks' do
    it 'should handle deadlock for save lock' do
      expect do
        @attachment.with_save_lock do
          @attachment.with_save_lock do
            puts 'should not execute this'
          end
        end
      end.to raise_error ThreadError
      expect(@attachment.instance_variable_get(:@save_lock).locked?).to eq false
    end

    it 'should handle deadlock on exceptions - save lock' do
      expect do
        @attachment.with_save_lock do
          raise TestException
        end
      end.to raise_error TestException
      expect(@attachment.instance_variable_get(:@save_lock).locked?).to eq false
    end

    it 'should handle deadlock on exceptions' do
      expect do
        @attachment.with_lock do
          raise TestException
        end
      end.to raise_error TestException
      expect(@attachment.instance_variable_get(:@attributes_lock).locked?).to eq false
    end

    it 'should handle deadlock for save lock' do
      expect do
        @attachment.with_lock do
          @attachment.with_lock do
            puts 'should not execute this'
          end
        end
      end.to raise_error ThreadError
      expect(@attachment.instance_variable_get(:@attributes_lock).locked?).to eq false
    end

    it 'should not raise error on nested status lock' do
      status = false
      expect do
        @attachment.with_status_lock do
          @attachment.with_status_lock do
            status = true
          end
        end
      end.not_to raise_error
      expect(status).to be_truthy
    end

    it 'should set is saving correctly without transaction' do
      @dummy.save
      expect(@attachment.is_saving?).to be_falsey
    end

    it 'should set is saving correctly within transaction' do
      Dummy.transaction do
        @dummy.save
        expect(@attachment.is_saving?).to be_truthy
      end
      expect(@attachment.is_saving?).to be_falsey
    end
  end

  def wait_for(queue)
    GBDispatch.dispatch_sync_on_queue queue do
      puts "waiting for #{queue}"
    end
  end
end