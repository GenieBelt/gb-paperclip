module Paperclip
  class VideoThumbnail < Processor

    attr_accessor :time_offset, :geometry, :whiny, :format, :convert_options,
                  :source_file_options, :image_file, :current_geometry

    def initialize(file, options = {}, attachment = nil)
      super
      geometry = options[:geometry].to_s
      @file    = file
      @crop    = geometry[-1, 1] == '#'
      @style   = options[:style]

      @time_offset          = options[:time_offset]
      @geometry             = options.fetch(:string_geometry_parser, Geometry).parse(geometry)
      @whiny                = options[:whiny].nil? ? true : options[:whiny]
      @convert_options      = options[:convert_options]
      @source_file_options  = options[:source_file_options]
      @format               = options[:format]
      @basename             = File.basename(file.path, File.extname(file.path))
      @file_geometry_parser = options.fetch(:file_geometry_parser, Geometry)

      @source_file_options  = @source_file_options.split(/\s+/) if @source_file_options.respond_to?(:split)
      @convert_options      = @convert_options.split(/\s+/) if @convert_options.respond_to?(:split)
    end

    alias target_geometry geometry

    def make
      dst = nil
      src = nil
      begin
        dst        = create_image
        parameters = []
        parameters << source_file_options
        parameters << ':source'
        parameters << transformation_command
        parameters << convert_options
        parameters << ':dest'
        parameters = parameters.flatten.compact.join(' ').strip.squeeze(' ')
        src        = dst
        dst        = Tempfile.new([@basename, ".#{@format}"])
        dst.binmode
        success = convert(parameters, :source => "#{File.expand_path(src.path)}[0]", :dest => File.expand_path(dst.path))
        @attachment.finished_processing @style if @attachment && @style
        success
      rescue Cocaine::ExitStatusError
        @attachment.failed_processing @style if @attachment && @style
        dst.close! if dst && dst.respond_to?(:close!)
        raise Paperclip::Error, "There was an error processing the thumbnail for #{@basename}" if @whiny
      rescue Cocaine::CommandNotFoundError
        @attachment.failed_processing @style if @attachment && @style
        dst.close! if dst && dst.respond_to?(:close!)
        raise Paperclip::Errors::CommandNotFoundError.new('Could not run the `convert` command. Please install ImageMagick.') if whiny
      rescue Paperclip::Errors::CommandNotFoundError => e
        @attachment.failed_processing @style if @attachment && @style
        dst.close! if dst && dst.respond_to?(:close!)
        raise e if @whiny
      rescue Exception => e
        @attachment.failed_processing @style if @attachment && @style
        dst.close! if dst && dst.respond_to?(:close!)
        dst = nil
        raise e
      ensure
        begin
          src.close! if src && src.respond_to?(:close!)
        rescue Exception
          nil
        end
      end
      dst
    end

    # @return [Paperclip::Tempfile]
    def create_image
      dst = Tempfile.new([@basename, '.jpg'])
      dst.binmode
      unless time_offset
        duration      = get_duration(file).to_f
        half_of_movie = duration/2
        time_offset   = Time.at(half_of_movie).utc.strftime('%H:%M:%S.%L')
      end

      cmd = %Q[-itsoffset #{time_offset} -i "#{File.expand_path(file.path)}" -y -vcodec mjpeg -vframes 1 -an -f rawvideo ]
      #cmd << "-s #{geometry.to_s} " unless geometry.nil?
      cmd << %Q["#{File.expand_path(dst.path)}"]
      begin
        Paperclip.run('avconv', cmd)
      rescue Cocaine::CommandNotFoundError
        raise Paperclip::Errors::CommandNotFoundError.new('Could not run the `avconv` command. Please install libav')
      end
      @current_geometry = @file_geometry_parser.from_file(dst)
      @image_file       = dst
    end

    # Returns the command ImageMagick's +convert+ needs to transform the image
    # into the thumbnail.
    def transformation_command
      scale, crop = @current_geometry.transformation_to(@geometry, crop?)
      trans       = []
      trans << '-auto-orient'
      trans << '-resize' << %["#{scale}"] unless scale.nil? || scale.empty?
      trans << '-crop' << %["#{crop}"] << '+repage' if crop
      trans
    end

    def crop?
      @crop
    end

    def get_duration(file)
      begin
        cmd = %Q[-loglevel quiet -show_format_entry duration "#{File.expand_path(file.path)}" ]
        Paperclip.run('avprobe', cmd)
      rescue Cocaine::CommandNotFoundError
        raise Paperclip::Errors::CommandNotFoundError.new('Could not run the `avprobe` command. Please install libav')
      end
    end
  end
end