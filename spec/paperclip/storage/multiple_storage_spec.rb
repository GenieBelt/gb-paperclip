require 'spec_helper'

describe Paperclip::Storage::MultipleStorage do

  context 'Creating store proxies' do
    before do
      rebuild_model storage: :multiple_storage,
                    stores:  {
                        main:        {
                            storage: :fake,
                            foo:     :main,
                        },
                        backups:     [
                                         { storage: :fake, foo: :backup1 },
                                         { storage: :fake, foo: :backup2, path:
                                                    ':class/:hash_:style_foo.:extension', bar: :bar },
                                     ],
                        additional:  [
                                         { storage: :fake, foo: :additional1, path: ':id_:style.:extension' },
                                         { storage: :fake, foo: :additional2, path: ':style_id.:extension' },
                                     ],

                    },
                    backup_form: :sync,
                    path: ':extension/:id/:style.:extension',
                    hash_secret: '5613genies',
                    bar: :test


      @dummy  = Dummy.new
      @avatar = @dummy.avatar
    end

    it 'should setup main store' do
      expect(@dummy.avatar.main_store).to be_a Paperclip::Storage::StorageProxy
      expect(@dummy.avatar.main_store).to be_a Paperclip::Storage::Fake
      expect(@dummy.avatar.main_store.options_foo).to eq :main
    end

    it 'should setup backup stores' do
      expect(@dummy.avatar.backup_stores.length).to eq 2
      @dummy.avatar.backup_stores.each do |store|
        expect(store).to be_a Paperclip::Storage::StorageProxy
        expect(store).to be_a Paperclip::Storage::Fake
      end
      expect(@dummy.avatar.backup_stores.map(&:options_foo)).to include :backup1, :backup2
    end

    it 'should setup additional stores' do
      expect(@dummy.avatar.additional_stores.length).to eq 2
      @dummy.avatar.additional_stores.each do |store|
        expect(store).to be_a Paperclip::Storage::StorageProxy
        expect(store).to be_a Paperclip::Storage::Fake
      end
      expect(@dummy.avatar.additional_stores.map(&:options_foo)).to include :additional1, :additional2
    end

    it 'should propagate general settings to other stores' do
      expect(@dummy.avatar.main_store.options_bar).to eq :test
      expect(@dummy.avatar.backup_stores.map(&:options_bar)).to include :test, :bar
      expect(@dummy.avatar.additional_stores.map(&:options_bar)).to eq [:test, :test]
    end

    it 'should use always parent path settings' do
      file          = File.open(fixture_file('5k.png'))
      @dummy.avatar = file

      expect(@dummy.avatar.path(:original)).to eq 'png//original.png'
      expect(@dummy.avatar.main_store.path(:original)).to eq 'png//original.png'
      @dummy.avatar.backup_stores.each do |store|
        expect(store.path(:original)).to eq 'png//original.png'
      end
      @dummy.avatar.additional_stores.each do |store|
        expect(store.path(:original)).to eq 'png//original.png'
      end
      file.close
    end
  end

  context 'paperclip store methods' do
    before do
      rebuild_model storage:     :multiple_storage,
                    stores:      {
                        main:       {
                            storage: :fake,
                            foo:     :main,
                        },
                        backups:    [
                                        { storage: :fake },
                                        { storage: :fake },
                                    ],
                        additional: [
                                        { storage: :fake },
                                        { storage: :fake },
                                    ],

                    },
                    backup_form: :async,
                    path:        ':id/:style.:extension',
                    styles:      {
                        thumb: '80x80>'
                    }
    end

    context 'exists?' do
      it 'should delegate call to main store' do
        dummy = Dummy.new
        dummy.avatar.main_store.expects(:exists?).with(:original)
        dummy.avatar.backup_stores.each do |store|
          store.expects(:exists?).never
        end
        dummy.avatar.additional_stores.each do |store|
          store.expects(:exists?).never
        end
        dummy.avatar.exists? :original
      end
    end

    context 'flush_writes' do
      before(:each) do
        @dummy        = Dummy.create!
        @file         = File.open(fixture_file('5k.png'))
        @dummy.avatar = @file
        @avatar       = @dummy.avatar
      end

      after(:each) do
        @file.close
      end

      it 'should call it for each thread' do
        dummy  = Dummy.new
        stores = [dummy.avatar.main_store, dummy.avatar.backup_stores, dummy.avatar.additional_stores].flatten
        stores.each do |store|
          store.expects(:flush_writes)
        end
        dummy.avatar.flush_writes
      end

      it 'is rewinded after flush_writes' do
        @dummy.avatar.instance_eval 'def after_flush_writes; end'

        files = @dummy.avatar.queued_for_write.values
        @dummy.save
        expect(files.none?(&:eof?)).to be_truthy
      end

      it 'is removed after after_flush_writes' do
        paths = @dummy.avatar.queued_for_write.values.map(&:path)
        @dummy.save
        expect(paths.none? { |path| File.exist?(path) }).to be_truthy
      end

      it 'should write on proper threads' do
        @dummy.save
        expect(@avatar.main_store.save_thread).to eq Thread.current
        @avatar.backup_stores.each { |store| expect(store.save_thread).not_to eq Thread.current }
        @avatar.additional_stores.each { |store| expect(store.save_thread).not_to eq Thread.current }
      end

      it 'should be able to run backup save synchronously' do
        @avatar.instance_variable_set :@backup_sync, true
        @dummy.save
        expect(@avatar.main_store.save_thread).to eq Thread.current
        @avatar.backup_stores.each { |store| expect(store.save_thread).to eq Thread.current }
        @avatar.additional_stores.each { |store| expect(store.save_thread).not_to eq Thread.current }
      end

      context 'asynchronous backup' do
        it 'should handle save errors' do
          @avatar.backup_stores.last.stubs(:flush_writes).raises(ArgumentError.new 'backup failed!')
          expect { @avatar.flush_writes }.to raise_error ArgumentError, 'backup failed!'
        end
      end

      context 'queued_for_write' do
        it 'should call lock when copying queues for write' do
          @avatar.expects(:with_lock).with(anything)
          @avatar.flush_writes
        end

        it 'should lock queue for write for time of copying' do
          count    = 0
          run_loop = true
          Thread.new do
            while run_loop
              count            += 1
              previous_adapter = nil
              @avatar.change_queued_for_write do |queue|
                previous_adapter = queue[:loop]
                queue[:loop]     = Paperclip.io_adapters.for("#{count}\n")
              end
              previous_adapter.close if previous_adapter
              sleep 0.0001
            end
            Thread.exit
          end
          expect { @avatar.flush_writes }.not_to raise_error
          run_loop = false
        end

        it 'should copy original file for queue for write for backups' do
          @avatar.send :set_write_queue_for_stores
          expect(@avatar.main_store.queued_for_write.keys.sort).to eq [:original, :thumb]
          @avatar.additional_stores.each do |store|
            expect(store.queued_for_write.keys.sort).to eq [:original, :thumb]
          end
          @avatar.backup_stores.each do |store|
            expect(store.queued_for_write.keys).not_to include :thumb
            expect(store.queued_for_write.keys).to eq [:original]
          end
        end
      end
    end
  end
end