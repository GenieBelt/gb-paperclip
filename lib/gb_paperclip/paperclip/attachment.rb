require 'paperclip/attachment'
require 'gb_paperclip/paperclip/has_attached_file'
module Paperclip
  class Attachment
    module SaveExtension
      def initialize(*args)
        @processor_info_lock = Mutex.new
        @status_lock         = Mutex.new
        @attributes_lock     = Mutex.new
        @save_lock           = Mutex.new
        @processor_tracker   = []
        super
      end

      def save
        result = nil
        with_status_lock do
          with_lock do
            @queued_for_write = @queued_for_write.delete_if { |key, value| key != :original &&(value.nil? || value.kind_of?(Paperclip::NilAdapter)) }
          end
          result = super
        end
        result
      end

      def is_saving?
        with_status_lock do
          !!@is_saving
        end
      end

      def is_saving!
        with_status_lock do
          @is_saving = true
        end
      end

      def is_saved!
        with_status_lock do
          @is_saving = false
        end
      end

      def force_close!
        unlink_files([@file])
      end

      def unlink_files(files)
        super files&.compact
      end

      def post_process_style(name, style) #:nodoc:
        begin
          processing style
          raise RuntimeError.new("Style #{name} has no processors defined.") if style.processors.blank?
          intermediate_files = []

          processor_result = style.processors.inject(@queued_for_write[:original]) do |file, processor|
            file = Paperclip.processor(processor).make(file, style.processor_options, self)
            intermediate_files << file if file && file != queued_for_write[:original]
            file
          end
          with_lock do
            @queued_for_write[name] = processor_result
            if @queued_for_write[name].nil?
              @queued_for_write.delete name
            else
              unadapted_file          = @queued_for_write[name]
              @queued_for_write[name] = Paperclip.io_adapters.for(@queued_for_write[name])
              unadapted_file.close if unadapted_file.respond_to?(:close)
            end
            @queued_for_write[name]
          end
        rescue Paperclip::Errors::NotIdentifiedByImageMagickError => e
          failed_processing style
          log("An error was received while processing: #{e.inspect}")
          (@errors[:processing] ||= []) << e.message if @options[:whiny]
        rescue Exception => e
          failed_processing style
          raise e
        ensure
          unlink_files(intermediate_files)
        end
      end

      def queued_for_write
        with_lock do
          @queued_for_write
        end
      end

      def staged?
        with_lock do
          super
        end
      end

      def dirty?
        with_status_lock do
          super
        end
      end

      def is_new?
        with_status_lock do
          !@instance.persisted? && @instance.new_record?
        end
      end

      def with_lock(&block)
        begin
          @attributes_lock.lock
          block.call
        ensure
          @attributes_lock.unlock if @attributes_lock.owned?
        end
      end

      def with_save_lock(&block)
        begin
          @save_lock.lock
          block.call
        ensure
          @save_lock.unlock if @save_lock.owned?
        end
      end

      def with_status_lock(&block)
        @status_lock.lock unless @status_lock.owned?
        block.call
      ensure
        @status_lock.unlock if @status_lock.owned?
      end

      def change_queued_for_write(&block)
        begin
          @attributes_lock.lock
          block.call(@queued_for_write)
        ensure
          @attributes_lock.unlock if @attributes_lock.owned?
        end
      end
    end

    prepend SaveExtension

    def reprocess!(*style_args)
      saved_only_process, @options[:only_process]     = @options[:only_process], style_args
      saved_preserve_files, @options[:preserve_files] = @options[:preserve_files], true
      @reprocessing                                   = true
      begin
        assign(self)
        @queued_for_write.delete(:original) unless process_style?(:original, only_process)
        save
        instance.save
      rescue Errno::EACCES => e
        warn "#{e} - skipping file."
        false
      ensure
        @options[:only_process]   = saved_only_process
        @options[:preserve_files] = saved_preserve_files
        @reprocessing             = false
      end
    end

    def assign_attributes
      @queued_for_write[:original] = @file
      unless @reprocessing && !process_style?(:original, only_process)
        assign_file_information
        assign_fingerprint { @file.fingerprint }
        assign_timestamps
      end
    end

    def reset_file_if_original_reprocessed
      unless @reprocessing && !process_style?(:original, only_process)
        instance_write(:file_size, @queued_for_write[:original].size)
        assign_fingerprint { @queued_for_write[:original].fingerprint }
        reset_updater
      end
    end

    def post_process(*style_args) #:nodoc:
      return if @queued_for_write[:original].nil? && !@reprocessing

      instance.run_paperclip_callbacks(:post_process) do
        instance.run_paperclip_callbacks(:"#{name}_post_process") do
          if !@options[:check_validity_before_processing] || !instance.errors.any?
            post_process_styles(*style_args)
          end
        end
      end
    end

    def processing(style)
      style = get_style_name(style)
      begin
        @processor_info_lock.lock
        @processor_tracker ||= []
        if @processor_tracker.count == 0
          if is_dirty? || is_new?
            @instance.processing       = true
            @instance.processed_styles ||= []
          else
            ensure_is_created do
              @instance.lock!
              @instance.update_columns(processing: true, processed_styles: @instance.processed_styles || [])
            end
          end
        end
        @processor_tracker << style
      ensure
        @processor_info_lock.unlock if @processor_info_lock.owned?
      end
      @processor_tracker
    end

    def failed_processing(style)
      style = get_style_name(style)
      is_included = @processor_info_lock.synchronize { @processor_tracker.include? style }
      return unless is_included
      processor_info_lock.synchronize do
        @processor_tracker.delete style
      end
      save_processing_info
      @processed_styles
    end

    def finished_processing(style)
      style = get_style_name(style)
      is_included = processor_info_lock.synchronize { @processor_tracker.include? style }
      return unless is_included
      processor_info_lock.synchronize do
        @processor_tracker.delete style
        @processed_styles ||= []
        @processed_styles << style
      end
      save_processing_info
      @processed_styles
    end

    def is_dirty?
      with_status_lock do
        !!@dirty
      end
    end

    # :nodoc:
    def staged_path(style_name = default_style)
      if staged? && queued_for_write[style_name]
        queued_for_write[style_name].path
      end
    end

    private

    def dirty!
      status_lock.synchronize { @dirty = true }
    end

    # @return [Mutex]
    def processor_info_lock
      @processor_info_lock
    end

    # @return [Mutex]
    def status_lock
      @status_lock
    end

    def get_style_name(style)
      if style.is_a? Paperclip::Style
        style = style.name
      end
      style
    end

    def save_processing_info
      with_save_lock do
        begin
          @processor_info_lock.lock
          @processed_styles ||= []
          if @processor_tracker.count == 0
            if is_dirty? || is_new?
              instance.processing       = false
              instance.processed_styles = @processed_styles
            else
              ensure_is_created do
                instance.run_paperclip_callbacks(:async_post_process) do
                  instance.with_lock do
                    instance.update_column :processing, false
                    instance.update_column :processed_styles, @processed_styles
                    instance.reload
                  end
                end
              end
            end
          end
        ensure
          @processor_info_lock.unlock if @processor_info_lock.owned?
        end
      end
    end

    def ensure_is_created(timeout=5.0, &block)
      while is_saving?
        sleep 0.001
      end
      retries = 0
      begin
        raise ActiveRecord::RecordNotFound unless instance.persisted?
        @instance.class.transaction do
          block.call
        end
      rescue ActiveRecord::RecordNotFound, ActiveRecord::ActiveRecordError => e
        if retries < timeout / 0.001
          retries += 1
          sleep 0.001
          retry
        else
          raise e
        end
      end
    end
  end
end