require 'spec_helper'
require 'zip'

describe Paperclip::ZipEntryAdapter do

  before :all do
    entries = []
    Zip::File.open(fixture_file('5k.png.zip')) do |zip_file|
      zip_file.each do |entry|
        entries << entry
      end
    end
    expect(Paperclip.io_adapters.for(entries.last)).to be_a_kind_of Paperclip::ZipEntryAdapter
  end

  context 'a new instance' do
    context 'with normal file' do
      before do
        @entries       = []
        @original_file = File.new(fixture_file('5k.png'))
        @original_file.binmode
        Zip::File.open(fixture_file('5k.png.zip')) do |zip_file|
          zip_file.each do |entry|
            @entries << entry
          end
        end
        @entry = @entries.last
      end

      after do
        @original_file.close
        @subject.close if @subject
      end

      context 'doing normal things' do
        before do
          @subject = Paperclip.io_adapters.for(@entry)
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
          expected = Digest::SHA512.file(@original_file.path).to_s
          expect(@subject.fingerprint).to eq expected
        end

        it 'reads the contents of the file' do
          expected = @original_file.read
          expect(@subject.read).to eq expected
          expect(expected.length > 0).to be_truthy
        end
      end

      context 'file with multiple possible content type' do
        before do
          allow(MIME::Types).to receive(:type_for).and_return([MIME::Type.new('content-type' => 'image/x-png'), MIME::Type.new('content-type' => 'image/png')])
          @subject = Paperclip.io_adapters.for(@entry)
        end

        it 'prefers officially registered mime type' do
          expect(@subject.content_type).to eq 'image/png'
        end

        it 'returns content type as a string' do
          expect(@subject.content_type).to be_a String
        end
      end
    end

    context 'filename with restricted characters' do
      before do
        @entries       = []
        @original_file = File.new(fixture_file('5k.png'))
        Zip::File.open(fixture_file('5k.png.zip')) do |zip_file|
          zip_file.each do |entry|
            @entries << entry
          end
        end
        @entry = @entries.last
        allow(@entry).to receive(:name).and_return('image:restricted.png')
        allow(@entry).to receive(:name).and_return('image:restricted.png')
        @subject = Paperclip.io_adapters.for(@entry)
      end

      after do
        @original_file.close
        @subject.close
      end

      it 'does not generate filenames that include restricted characters' do
        expect(@subject.original_filename).to eq 'image_restricted.png'
      end

      it 'does not generate paths that include restricted characters' do
        expect(@subject.path).to_not match(/:/)
      end
    end
  end
end