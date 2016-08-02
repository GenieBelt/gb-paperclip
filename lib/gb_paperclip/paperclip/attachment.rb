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
        with_save_lock do
          begin
            @status_lock.lock
            @is_saving = true
            @attributes_lock.synchronize do
              @queued_for_write = @queued_for_write.delete_if { |key, value| key != :original &&(value.nil? || value.kind_of?(Paperclip::NilAdapter)) }
            end
            result = super
          ensure
            @status_lock.unlock if @status_lock.owned?
          end
          @status_lock.synchronize { @is_saving = false }
          result
        end
      end

      def is_saving?
        status_lock.synchronize { !!@is_saving }
      end

      def unlink_files(files)
        super files.compact
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
        @attributes_lock.synchronize { @queued_for_write }
      end

      def staged?
        @attributes_lock.synchronize { super }
      end

      def dirty?
        @status_lock.synchronize { super }
      end

      def is_new?
        begin
          @status_lock.lock
          @instance.new_record? && !@instance.persisted?
        ensure
          @status_lock.unlock if @status_lock.owned?
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
              @instance.update_attribute :processing, true
              @instance.processed_styles ||= []
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
      status_lock.synchronize { @dirty }
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
              instance.run_paperclip_callbacks(:async_post_process) do
                ensure_is_created do
                  instance.with_lock do
                    instance.update_column :processing, false
                    instance.update_column :processed_styles, @processed_styles
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
      retries = 0
      begin
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