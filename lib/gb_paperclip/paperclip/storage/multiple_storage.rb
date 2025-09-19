module Paperclip
  module Storage
    module MultipleStorage
      def self.extended(base)
        base.instance_eval do

          main_store_options           = Hash.new.merge @options
          main_store_options[:storage] = main_store_options[:stores][:main][:storage]
          main_store_options           = main_store_options.merge(main_store_options[:stores][:main])
          main_store_options.delete :stores

          @main_store               = Paperclip::Storage::StorageProxy.new main_store_options, self
          @options[:url]            = @main_store.options[:url]
          @additional_stores        = []
          additional_stores_options = Hash.new.merge @options
          (additional_stores_options[:stores][:additional] || []).each do |store_option|
            additional_store_options           = Hash.new.merge @options
            additional_store_options[:storage] = store_option[:storage]
            @additional_stores << Paperclip::Storage::StorageProxy.new(additional_store_options.merge(store_option), self)
          end
          @backup_sync           = @options[:backup_form] == :sync
          @backup_stores         = []
          backups_stores_options = Hash.new.merge @options
          (backups_stores_options[:stores][:backups] || []).each do |store_option|
            backup_store_options           = Hash.new.merge @options
            backup_store_options[:storage] = store_option[:storage]
            @backup_stores << Paperclip::Storage::StorageProxy.new(backup_store_options.merge(store_option), self)
          end
        end
      end

      # @return [Paperclip::Storage::Proxy]
      def main_store
        @main_store
      end

      # @return [Array<Paperclip::Storage::Proxy>]
      def additional_stores
        @additional_stores
      end

      # @return [Array<Paperclip::Storage::Proxy>]
      def backup_stores
        @backup_stores
      end

      def exists?(style_name = default_style)
        @main_store.exists?(style_name)
      end

      def flush_writes #:nodoc:
        critical_threads = []
        set_write_queue_for_stores
        @backup_stores.each do |store|
          if @backup_sync
            store.flush_writes
          else
            thr = on_new_thread do
              begin
                store.flush_writes
              ensure
                store.after_flush_writes
              end
            end
            critical_threads << thr
          end
        end
        @additional_stores.each do |store|
          on_new_thread do
            begin
              store.flush_writes
            ensure
              store.after_flush_writes #close all copied files
            end
          end
        end
        @main_store.flush_writes
        while critical_threads.any?
          critical_threads.delete_if { |thread| !thread.alive? && !thread[:error] }
          thread_with_error = critical_threads.select { |thread| thread[:error] }.first
          raise thread_with_error[:error] if thread_with_error
          sleep 0.1
        end
        @queued_for_write
      rescue => e
        close_all_queue_files
        raise e
      end

      def flush_deletes #:nodoc:
        @additional_stores.each do |store|
          store.queued_for_delete = [] + @queued_for_delete
          on_new_thread do
            store.flush_deletes
          end
        end

        @main_store.queued_for_delete = [] + @queued_for_delete
        @main_store.flush_deletes

        @queued_for_delete = []
      end

      def copy_to_local_file(style, local_dest_path)
        result = @main_store.copy_to_local_file(style, local_dest_path)
        return result if result
        @additional_stores.each do |store|
          begin
            result = store.copy_to_local_file(style, local_dest_path)
          rescue Exception => e
            log("Cannot copy file form additional storage. #{e.message}")
            result = nil
          end
          return result if result
        end
        @backup_stores.each do |store|
          begin
            result = store.copy_to_local_file(style, local_dest_path)
          rescue Exception => e
            log("Cannot copy file form backup storage. #{e.message}")
            result = nil
          end
          return result if result
        end
        false
      end

      def method_missing(method, *args, &block)
        if @main_store.respond_to? method
          @main_store.send(method, *args, &block)
        else
          super
        end
      end

      private

      def set_write_queue_for_stores
        with_lock do
          backup_queued_for_write = Hash.new.merge(@queued_for_write).delete_if { |style, _| style != :original }
          @backup_stores.each do |store|
            store.queued_for_write = backup_queued_for_write
          end
          @main_store.queued_for_write = @queued_for_write
          @additional_stores.each do |store|
            store.queued_for_write = @queued_for_write
          end
          after_flush_writes
          @queued_for_write = {}
        end
      end

      def close_all_queue_files
        with_lock do
          @backup_stores.each do |store|
            store.close_all_files!
          end
          @main_store.close_all_files!
          @additional_stores.each do |store|
            store.close_all_files!
          end
        end
      end

      def on_new_thread(&block)
        (thr = Thread.new do
          begin
            ActiveRecord::Base.connection_pool.with_connection do
              block.call
            end
          rescue Exception => e
            Thread.current[:error] = e
          ensure
            ActiveRecord::Base.connection_handler.clear_active_connections!
          end
        end).abort_on_exception = false
        thr
      end
    end
  end
end
