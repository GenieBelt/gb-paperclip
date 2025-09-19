require 'spec_helper'
require 'gb_paperclip/paperclip/validators/quarantine'

describe Paperclip::Validators::MediaTypeSpoofDetectionValidator do
  before(:all) do
    rebuild_model(validate_media_type: true)
  end

  before (:each) do
    @dummy = Dummy.new
  end

  def build_validator(options = {})
    @validator = Paperclip::Validators::MediaTypeSpoofDetectionValidator.new(options.merge(
        attributes: :avatar
    ))
  end


  it 'copy file to quarantine folder if spoofed' do
    build_validator
    file = File.new(fixture_file('5k.png'), 'rb')
    @dummy.avatar.assign(file)
    @dummy.avatar_file_name = '5k.pdf'

    @validator.validate(@dummy)

    expect(File.directory? 'tmp/quarantine').to be_truthy
    expect(Dir['tmp/quarantine/*_5k.pdf']).not_to be_empty
    file.close
  end
end
