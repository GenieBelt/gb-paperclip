module Paperclip
  class VideoThumbnail < Processor

    attr_accessor :time_offset, :geometry, :whiny, :format, :convert_options,
                  :source_file_options

    def initialize(file, options = {}, attachment = nil)
      super
      geometry = options[:geometry].to_s
      @file    = file
      @crop    = geometry[-1, 1] == '#'

      @time_offset = options[:time_offset] || '-4'
      unless options[:geometry].nil? || (@geometry = Geometry.parse(options[:geometry])).nil?
        @geometry.width    = (@geometry.width / 2.0).floor * 2.0
        @geometry.height   = (@geometry.height / 2.0).floor * 2.0
        @geometry.modifier = ''
      end
      @current_geometry    = options.fetch(:file_geometry_parser, Geometry).from_file(file)
      @whiny               = options[:whiny].nil? ? true : options[:whiny]
      @convert_options     = options[:convert_options]
      @source_file_options = options[:source_file_options]
      @format              = options[:format]
      @basename            = File.basename(file.path, File.extname(file.path))
    end

    def make
      dst = Tempfile.new([@basename, 'jpg'].compact.join("."))
      dst.binmode
      src = nil

      cmd = %Q[-itsoffset #{time_offset} -i "#{File.expand_path(file.path)}" -y -vcodec mjpeg -vframes 1 -an -f rawvideo ]
      cmd << "-s #{geometry.to_s} " unless geometry.nil?
      cmd << %Q["#{File.expand_path(dst.path)}"]

      begin
        success = Paperclip.run('ffmpeg', cmd)
        if @format != :jpg
          parameters = []
          parameters << source_file_options
          parameters << ":source"
          parameters << transformation_command
          parameters << convert_options
          parameters << ":dest"
          parameters = parameters.flatten.compact.join(" ").strip.squeeze(" ")
          src        = dst
          dst        = Tempfile.new([@basename, "#{@format}"].compact.join("."))
          dst.binmode
          success = convert(parameters, :source => "#{File.expand_path(src.path)}[0]", :dest => File.expand_path(dst.path))
        end
        @attachment.finished_processing @style
      rescue Cocaine::CommandNotFoundError => e
        @attachment.failed_processing @style if @attachment && @style
        dst.close! if dst && dst.respond_to?(:close!)
        raise Paperclip::Errors::CommandNotFoundError.new('Could not run the `ffmpeg` command. Please install FFmpeg') if whiny
      rescue Exception => e
        @attachment.failed_processing @style if @attachment && @style
        dst.close! if dst && dst.respond_to?(:close!)
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

    # Returns the command ImageMagick's +convert+ needs to transform the image
    # into the thumbnail.
    def transformation_command
      scale, crop = @current_geometry.transformation_to(@geometry, crop?)
      trans       = []
      trans << "-resize" << %["#{scale}"] unless scale.nil? || scale.empty?
      trans << "-crop" << %["#{crop}"] << "+repage" if crop
      trans
    end

    def crop?
      @crop
    end
  end
end