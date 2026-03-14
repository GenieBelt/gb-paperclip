require 'spec_helper'
require 'gb_paperclip/paperclip/io_adapters/copy_adapter'

describe Paperclip::CopyAdapter do
  context 'a new instance' do
    context 'with normal file adapter' do
      before do
        @file = File.new(fixture_file('5k.png'))
        @file.binmode
        @original_adapter = Paperclip.io_adapters.for(@file)
      end

      after do
        @file.close
        @original_adapter.close
        @subject.close if @subject
      end

      context 'doing normal things' do
        before do
          #@subject = Paperclip.io_adapters.for(@original_adapter)
          #expect(@subject).to be_kind_of Paperclip::CopyAdapter
          @subject = Paperclip::CopyAdapter.new(@original_adapter)
        end

        it 'uses the original filename to generate the tempfile' do
          expect(@subject.path.ends_with?('.png')).to be_truthy
        end

        it 'gets the right filename' do
          expect(@subject.original_filename).to eq '5k.png'
        end

        it 'forces binmode on tempfile' do
          expect(@subject.instance_variable_get('@tempfile').binmode?).to be_truthy
        end

        it 'gets the content type' do
          expect(@subject.content_type).to eq 'image/png'
        end

        it 'returns content type as a string' do
          expect(@subject.content_type).to be_a String
        end

        it "gets the file's size" do
          expect(@subject.size).to eq 4456
        end

        it 'returns false for a call to nil?' do
          expect(@subject.nil?).to be_falsey
        end

        it 'generates a SHA512 hash of the contents' do
          expected = Digest::SHA512.file(@file.path).to_s
          expect(@subject.fingerprint).to eq expected
        end

        it 'reads the contents of the file' do
          expected = @file.read
          expect(@subject.read).to eq expected
          expect(expected.length > 0).to be_truthy
        end

        it 'has different temp files then original' do
          expect(@subject.instance_variable_get('@tempfile')).not_to eq @original_adapter.instance_variable_get('@tempfile')
        end

        it 'has different path then original' do
          expect(@subject.path).not_to eq @original_adapter.path
        end

        it 'returns true for a call to assignment?' do
          expect(@subject.assignment?).to be_truthy
        end
      end

      context 'file with multiple possible content type' do
        before do
          allow(MIME::Types).to receive(:type_for).and_return([MIME::Type.new('content-type' => 'image/x-png'), MIME::Type.new('content-type' => 'image/png')])
          @subject = Paperclip::CopyAdapter.new(@original_adapter)
        end

        it 'prefers officially registered mime type' do
          expect(@subject.content_type).to eq 'image/png'
        end

        it 'returns content type as a string' do
          expect(@subject.content_type).to be_a String
        end
      end
    end

    context 'with attachment adapter' do
      before do
        rebuild_model path: 'tmp/:class/:attachment/:style/:filename', styles: { thumb: '50x50' }
        @attachment = Dummy.new.avatar
        @file       = File.new(fixture_file('5k.png'))
        @file.binmode

        @attachment.assign(@file)
        @attachment.save
        @original_adapter = Paperclip.io_adapters.for(@attachment)
      end

      after do
        @file.close
        @original_adapter.close
        @subject.close if @subject
      end

      context 'doing normal things' do
        before do
          #@subject = Paperclip.io_adapters.for(@original_adapter)
          #expect(@subject).to be_kind_of Paperclip::CopyAdapter
          @subject = Paperclip::CopyAdapter.new(@original_adapter)
        end

        it 'uses the original filename to generate the tempfile' do
          expect(@subject.path.ends_with?('.png')).to be_truthy
        end

        it 'gets the right filename' do
          expect(@subject.original_filename).to eq '5k.png'
        end

        it 'forces binmode on tempfile' do
          expect(@subject.instance_variable_get('@tempfile').binmode?).to be_truthy
        end

        it 'gets the content type' do
          expect(@subject.content_type).to eq 'image/png'
        end

        it 'returns content type as a string' do
          expect(@subject.content_type).to be_a String
        end

        it "gets the file's size" do
          expect(@subject.size).to eq 4456
        end

        it 'returns false for a call to nil?' do
          expect(@subject.nil?).to be_falsey
        end

        it 'returns true for a call to assignment?' do
          expect(@subject.assignment?).to be_truthy
        end

        it 'generates a SHA512 hash of the contents' do
          expected = Digest::SHA512.file(@file.path).to_s
          expect(@subject.fingerprint).to eq expected
        end

        it 'reads the contents of the file' do
          expected = @file.read
          expect(@subject.read).to eq expected
          expect(expected.length > 0).to be_truthy
        end

        it 'has different temp files then original' do
          expect(@subject.instance_variable_get('@tempfile')).not_to eq @original_adapter.instance_variable_get('@tempfile')
        end

        it 'has different path then original' do
          expect(@subject.path).not_to eq @original_adapter.path
        end
      end
    end
    context 'with DataUri adapter' do
      after do
        @original_adapter.close
        @subject.close if @subject
      end

      before do
        @contents         = "data:image/png;base64,#{original_base64_content}"
        @original_adapter = Paperclip.io_adapters.for(@contents)
        @subject          = Paperclip::CopyAdapter.new(@original_adapter)
      end

      it 'gets the right filename' do
        expect(@subject.original_filename).to eq 'data'
      end

      it 'forces binmode on tempfile' do
        expect(@subject.instance_variable_get('@tempfile').binmode?).to be_truthy
      end

      it 'gets the content type' do
        expect(@subject.content_type).to eq 'image/png'
      end

      it 'returns content type as a string' do
        expect(@subject.content_type).to be_a String
      end

      it "gets the file's size" do
        expect(@subject.size).to eq 4456
      end

      it 'returns false for a call to nil?' do
        expect(@subject.nil?).to be_falsey
      end

      it 'returns true for a call to assignment?' do
        expect(@subject.assignment?).to be_truthy
      end

      it 'generates a SHA512 hash of the contents' do
        expect(@subject.fingerprint).to eq Digest::SHA512.hexdigest(Base64.decode64(original_base64_content))
      end

      it 'reads the contents of the file' do
        expect(@subject.read).to eq @original_adapter.read
      end

      it 'has different temp files then original' do
        expect(@subject.instance_variable_get('@tempfile')).not_to eq @original_adapter.instance_variable_get('@tempfile')
      end

      it 'has different path then original' do
        expect(@subject.path).not_to eq @original_adapter.path
      end

      def original_base64_content
        Base64.encode64(original_file_contents)
      end

      def original_file_contents
        @original_file_contents ||= File.read(fixture_file('5k.png'))
      end
    end
    context 'with empty string adapter' do
      before do
        @original_adapter = Paperclip.io_adapters.for('')
      end

      it 'should not fail when creating with empty string' do
        expect { Paperclip::CopyAdapter.new(@original_adapter) }.not_to raise_error
      end

      it 'returns false for a call to assignment?' do
        expect(Paperclip::CopyAdapter.new(@original_adapter).assignment?).to be_falsey
      end

      it 'returns false for a call to nil?' do
        expect(Paperclip::CopyAdapter.new(@original_adapter).nil?).to be_falsey
      end
    end
    context 'with http url proxy adapter' do
      before do
        mime_type = double
        allow(mime_type).to receive(:presence).and_return('image/png')
        @open_return = StringIO.new('xxx')
        allow(@open_return).to receive(:meta).and_return('content-type' => mime_type)
        allow(@open_return).to receive(:content_type).and_return('image/png')
        allow_any_instance_of(Paperclip::HttpUrlProxyAdapter).to receive(:download_content).and_return(@open_return)
        @url              = 'http://thoughtbot.com/images/thoughtbot-logo.png'
        @original_adapter = Paperclip.io_adapters.for(@url)
        @subject          = Paperclip::CopyAdapter.new(@original_adapter)
      end

      after do
        @original_adapter.close
        @subject.close
      end


      it 'gets the right filename' do
        expect(@subject.original_filename).to eq 'thoughtbot-logo.png'
      end

      it 'forces binmode on tempfile' do
        expect(@subject.instance_variable_get('@tempfile').binmode?).to be_truthy
      end

      it 'gets the content type' do
        expect(@subject.content_type).to eq 'image/png'
      end

      it 'returns content type as a string' do
        expect(@subject.content_type).to be_a String
      end

      it "gets the file's size" do
        expect(@subject.size).to eq @open_return.size
      end

      it 'returns false for a call to nil?' do
        expect(@subject.nil?).to be_falsey
      end

      it 'returns true for a call to assignment?' do
        expect(@subject.assignment?).to be_truthy
      end

      it 'generates a SHA512 hash of the contents' do
        expected = Digest::SHA512.hexdigest(@original_adapter.read)
        expect(@subject.fingerprint).to eq expected
      end

      it 'reads the contents of the file' do
        expected = @original_adapter.read
        expect(@subject.read).to eq expected
        expect(expected.length > 0).to be_truthy
      end

      it 'has different temp files then original' do
        expect(@subject.instance_variable_get('@tempfile')).not_to eq @original_adapter.instance_variable_get('@tempfile')
      end

      it 'has different path then original' do
        expect(@subject.path).not_to eq @original_adapter.path
      end
    end
    context 'with nil adapter' do
      before do
        @original_adapter = Paperclip.io_adapters.for(nil)
      end

      it 'should not fail when creating with nil adapter' do
        expect { Paperclip::CopyAdapter.new(@original_adapter) }.not_to raise_error
      end

      it 'returns true for a call to nil?' do
        expect(Paperclip::CopyAdapter.new(@original_adapter).nil?).to be_truthy
      end

      it "gets the file's size" do
        expect(Paperclip::CopyAdapter.new(@original_adapter).size).to eq 0
      end
    end
  end
end