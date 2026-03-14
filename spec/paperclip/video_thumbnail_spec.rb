require 'spec_helper'

describe Paperclip::VideoThumbnail do

  context 'An video' do
    before do
      @file = File.new(fixture_file('1m.3gp'), 'rb')
    end

    after { @file.close }

    [%w(600x600> 600x360),
     %w(400x400> 400x240),
     %w(32x32< 800x480),
     [nil, '800x480']
    ].each do |args|
      context "being thumbnailed with a geometry of #{args[0]}" do
        before do
          @thumb = Paperclip::VideoThumbnail.new(@file, geometry: args[0])
        end

        it 'starts with dimensions of 434x66' do
          cmd = %Q[ffprobe -loglevel error -of json -show_entries stream=width,height "#{@file.path}"]
          result = JSON.parse(`#{cmd}`)
          expect(result['streams'][1]['width']).to eq 800
          expect(result['streams'][1]['height']).to eq 480
        end

        it 'reports the correct target geometry' do
          assert_equal args[0].to_s, @thumb.target_geometry.to_s
        end

        context 'when made' do
          before do
            @thumb_result = @thumb.make
          end

          it 'is the size we expect it to be' do
            cmd = %Q[identify -format "%wx%h" "#{@thumb_result.path}"]
            assert_equal args[1], `#{cmd}`.chomp
          end
        end
      end
    end

    context 'being thumbnailed at 100x50 with cropping' do
      before do
        @thumb = Paperclip::VideoThumbnail.new(@file, geometry: '100x50#')
      end

      it "lets us know when a command isn't found versus a processing error" do
        old_path = ENV['PATH']
        begin
          Terrapin::CommandLine.path        = ''
          Paperclip.options[:command_path] = ''
          ENV['PATH']                      = ''
          assert_raises(Paperclip::Errors::CommandNotFoundError) do
            silence_stream(STDERR) do
              @thumb.make
            end
          end
        ensure
          ENV['PATH'] = old_path
        end
      end

      it 'reports its correct current and target geometries' do
        expect(@thumb.target_geometry.to_s).to eq '100x50#'
        @thumb.create_image
        expect(@thumb.current_geometry.to_s).to eq '800x480'
      end

      it 'reports its correct format' do
        expect(@thumb.format).to be_nil
      end

      it 'has whiny turned on by default' do
        expect(@thumb.whiny).to be_truthy
      end

      it 'has convert_options set to nil by default' do
        expect(@thumb.convert_options).to be_nil
      end

      it 'has source_file_options set to nil by default' do
        assert_equal nil, @thumb.source_file_options
      end

      it 'sends the right command to convert when sent #make' do
        expect(@thumb).to receive(:convert).with(':source -auto-orient -resize "100x" -crop "100x50+0+5" +repage :dest', anything)
        @thumb.make
      end

      it 'creates the thumbnail when sent #make' do
        dst = @thumb.make
        assert_match /100x50/, `identify "#{dst.path}"`
      end
    end

    it 'crops a EXIF-rotated image properly' do
      file  = File.new(fixture_file('7m.mov'))
      thumb = Paperclip::VideoThumbnail.new(file, geometry: '100x100')

      output_file = thumb.make

      command = Terrapin::CommandLine.new('identify', '-format %wx%h :file')
      assert_equal '56x100', command.run(file: output_file.path).strip
    end

    context 'being thumbnailed with source file options set' do
      before do
        @thumb = Paperclip::VideoThumbnail.new(@file,
                                               geometry:            '100x50#',
                                               source_file_options: '-strip')
      end

      it 'has source_file_options value set' do
        assert_equal ['-strip'], @thumb.source_file_options
      end

      it 'sends the right command to convert when sent #make' do
        expect(@thumb).to receive(:convert).with('-strip :source -auto-orient -resize "100x" -crop "100x50+0+5" +repage :dest', anything)
        @thumb.make
      end

      it 'creates the thumbnail when sent #make' do
        dst = @thumb.make
        assert_match /100x50/, `identify "#{dst.path}"`
      end

      context 'redefined to have bad source_file_options setting' do
        before do
          @thumb = Paperclip::VideoThumbnail.new(@file,
                                                 geometry:            '100x50#',
                                                 source_file_options: '-this-aint-no-option')
        end

        it 'errors when trying to create the thumbnail' do
          assert_raises(Paperclip::Error) do
            silence_stream(STDERR) do
              @thumb.make
            end
          end
        end
      end
    end

    context 'being thumbnailed with convert options set' do
      before do
        @thumb = Paperclip::VideoThumbnail.new(@file,
                                               geometry:        '100x50#',
                                               convert_options: '-strip -depth 8')
      end

      it 'has convert_options value set' do
        assert_equal %w"-strip -depth 8", @thumb.convert_options
      end

      it 'sends the right command to convert when sent #make' do
        expect(@thumb).to receive(:convert).with(':source -auto-orient -resize "100x" -crop "100x50+0+5" +repage -strip -depth 8 :dest', anything)
        @thumb.make
      end

      it 'creates the thumbnail when sent #make' do
        dst = @thumb.make
        assert_match /100x50/, `identify "#{dst.path}"`
      end

      context 'redefined to have bad convert_options setting' do
        before do
          @thumb = Paperclip::VideoThumbnail.new(@file,
                                                 geometry:        '100x50#',
                                                 convert_options: '-this-aint-no-option')
        end

        it 'errors when trying to create the thumbnail' do
          assert_raises(Paperclip::Error) do
            silence_stream(STDERR) do
              @thumb.make
            end
          end
        end

        it "lets us know when a command isn't found versus a processing error" do
          old_path = ENV['PATH']
          begin
            Terrapin::CommandLine.path        = ''
            Paperclip.options[:command_path] = ''
            ENV['PATH']                      = ''
            assert_raises(Paperclip::Errors::CommandNotFoundError) do
              silence_stream(STDERR) do
                @thumb.make
              end
            end
          ensure
            ENV['PATH'] = old_path
          end
        end
      end
    end

    context 'being thumbnailed with a blank geometry string' do
      before do
        @thumb = Paperclip::VideoThumbnail.new(@file,
                                               geometry:        '',
                                               convert_options: "-gravity center -crop \"300x300+0-0\"")
      end

      it 'does not get resized by default' do
        @thumb.create_image
        expect(@thumb.transformation_command).not_to include('-resize')
      end
    end

    context 'passing a custom file geometry parser' do
      after do
        Object.send(:remove_const, :GeoParser) if Object.const_defined?(:GeoParser)
      end

      it 'produces the appropriate transformation_command' do
        GeoParser = Class.new do
          def self.from_file(file)
            new
          end

          def transformation_to(target, should_crop)
            %w(SCALE CROP)
          end
        end

        thumb = Paperclip::VideoThumbnail.new(@file, geometry: '50x50', file_geometry_parser: ::GeoParser)
        thumb.create_image

        transformation_command = thumb.transformation_command

        assert transformation_command.include?('-crop'),
               %{expected #{transformation_command.inspect} to include '-crop'}
        assert transformation_command.include?('"CROP"'),
               %{expected #{transformation_command.inspect} to include '"CROP"'}
        assert transformation_command.include?('-resize'),
               %{expected #{transformation_command.inspect} to include '-resize'}
        assert transformation_command.include?('"SCALE"'),
               %{expected #{transformation_command.inspect} to include '"SCALE"'}
      end
    end

    context 'passing a custom geometry string parser' do
      after do
        Object.send(:remove_const, :GeoParser) if Object.const_defined?(:GeoParser)
      end

      it 'produces the appropriate transformation_command' do
        GeoParser = Class.new do
          def self.parse(s)
            new
          end

          def to_s
            '151x167'
          end
        end

        thumb = Paperclip::VideoThumbnail.new(@file, geometry: '50x50', string_geometry_parser: ::GeoParser)
        thumb.create_image

        transformation_command = thumb.transformation_command

        assert transformation_command.include?('"151x167"'),
               %{expected #{transformation_command.inspect} to include '151x167'}
      end
    end
  end

  context 'Attachment processing info' do
    before(:each) do
      @file       = File.new(fixture_file('7m.mov'), 'rb')
      @attachment = double
      @thumb      = Paperclip::VideoThumbnail.new(@file, { geometry: '100x100', style: :test }, @attachment)
    end

    after(:each) { @file.close }

    it 'should call finished processing style if successes' do
      expect(@attachment).to receive(:finished_processing).with(:test)
      @thumb.make
    end

    context 'should call failed processing style if' do
      it 'ffprobe not exists' do
        expect(@attachment).to receive(:failed_processing).with(:test)
        allow(@thumb).to receive(:get_duration).with(anything).and_raise(Terrapin::CommandNotFoundError.new '')
        expect { @thumb.make }.to raise_error Paperclip::Errors::CommandNotFoundError
      end

      it 'avconv not exists' do
        expect(@attachment).to receive(:failed_processing).with(:test)
        allow(@thumb).to receive(:create_image).and_raise(Terrapin::CommandNotFoundError.new '')
        expect { @thumb.make }.to raise_error Paperclip::Errors::CommandNotFoundError
      end

      it 'avconv or ffprobe have wrong params' do
        expect(@attachment).to receive(:failed_processing).with(:test)
        allow(@thumb).to receive(:create_image).and_raise(Terrapin::ExitStatusError.new '')
        expect { @thumb.make }.to raise_error(Paperclip::Error)
      end

      it 'image magick error' do
        expect(@attachment).to receive(:failed_processing).with(:test)
        old_path = ENV['PATH']
        begin
          Terrapin::CommandLine.path        = ''
          Paperclip.options[:command_path] = ''
          ENV['PATH']                      = ''
          expect do
            silence_stream(STDERR) do
              @thumb.make
            end
          end.to raise_error Paperclip::Errors::CommandNotFoundError
        ensure
          ENV['PATH'] = old_path
        end
      end

      it 'throws any error' do
        expect(@attachment).to receive(:failed_processing).with(:test)
        allow(@thumb).to receive(:create_image).and_raise('test error')
        expect { @thumb.make }.to raise_error(RuntimeError)
      end
    end
  end
end