# gb-paperclip

Extensions to [kt-paperclip](https://github.com/kreeti/kt-paperclip) with async processors, multi-backend storage, and media type validation.

## Installation

Add to your Gemfile using the GitHub Package Registry:

```ruby
source 'https://rubygems.pkg.github.com/geniebelt' do
  gem 'gb_paperclip'
end
```

**Requirements:**
- Ruby ≥ 3.0
- Rails/ActiveRecord ≥ 7.0

**System dependencies** (install based on features used):
- [ImageMagick](https://imagemagick.org/) — image thumbnails and PDF thumbnails
- [FFmpeg](https://ffmpeg.org/) — video thumbnails

## Local Development

Run tests against a specific Rails version using Appraisal:

```bash
bundle exec appraisal rails-8.1 rspec
```

Or set `BUNDLE_GEMFILE` directly for your session:

```bash
export BUNDLE_GEMFILE=gemfiles/rails_8.1.gemfile
bundle exec rspec
```

Available gemfiles are in the `gemfiles/` directory. After adding or changing `Appraisals`, regenerate them with:

```bash
bundle exec appraisal install
```

## Storage Backends

### S3

Extends Paperclip's built-in S3 storage with two additional methods:

- `expiring_url_with_name(time, style)` — generates a presigned URL that includes the original filename
- `get_file_stream(style)` — returns an IO stream for the stored file

Configure as you would standard Paperclip S3 storage:

```ruby
has_attached_file :file,
  storage: :s3,
  s3_credentials: { bucket: 'my-bucket', access_key_id: '...', secret_access_key: '...' }
```

### Glacier

Write-only cold storage backend for infrequently accessed files. Requires a `glacier_ids` column (hstore or json type) on the model.

```ruby
has_attached_file :file,
  storage: :glacier,
  glacier_credentials: { access_key_id: '...', secret_access_key: '...' },
  vault: 'my-vault',
  glacier_region: 'us-east-1',
  account_id: '-'  # '-' uses the credentials' account
```

### Multiple Storage

Fan-out writes to multiple storage backends simultaneously. Useful for mirroring uploads to S3 and a backup store.

```ruby
has_attached_file :file,
  storage: :multiple_storage,
  stores: {
    main: {
      storage: :s3,
      s3_credentials: { bucket: 'primary-bucket', access_key_id: '...', secret_access_key: '...' }
    },
    additional: [
      {
        storage: :s3,
        s3_credentials: { bucket: 'replica-bucket', access_key_id: '...', secret_access_key: '...' }
      }
    ],
    backups: [
      {
        storage: :glacier,
        glacier_credentials: { access_key_id: '...', secret_access_key: '...' },
        vault: 'archive-vault',
        glacier_region: 'us-east-1'
      }
    ]
  },
  backup_form: :async  # :sync or :async (default: :sync)
```

- `main` — primary store; reads and URL generation use this store
- `additional` — written synchronously alongside `main`
- `backups` — written synchronously or asynchronously (`:async` requires a background job setup)

## Processors

### Thumbnail

Standard image thumbnail processor (inherited from kt-paperclip) with added async processing callbacks. After processing completes, the attachment fires:

- `finished_processing` — called on the model instance when all styles are done
- `failed_processing` — called on the model instance if processing fails

```ruby
has_attached_file :avatar,
  styles: { medium: '300x300>', thumb: '100x100>' }
```

### PDF Thumbnail

Generates a thumbnail image from the first page of a PDF.

```ruby
has_attached_file :document,
  styles: {
    preview: {
      geometry: '800x600>',
      format: :png,
      processors: [:pdf_thumbnail]
    }
  }
```

### Video Thumbnail

Extracts a single frame from a video file as a thumbnail image. If `time_offset` is omitted, the frame is taken from the video's midpoint.

```ruby
has_attached_file :video,
  styles: {
    thumbnail: {
      geometry: '640x480>',
      format: :jpg,
      time_offset: '00:00:05',  # optional; defaults to video midpoint
      processors: [:video_thumbnail]
    }
  }
```

## Validators

### Quarantine (media type spoof detection)

Checks whether the file's actual MIME type matches its extension. If a mismatch is detected, the file is moved to `tmp/quarantine/` and a `:spoofed_media_type` validation error is added to the attachment.

```ruby
validates_attachment :file, media_type_spoof: true
```

### Spoof Warning

Non-blocking variant of spoof detection. Does not add a validation error; instead sets accessor attributes on the model:

- `file_spoof_warning` — `true` if a mismatch was detected
- `file_spoof_content_type` — the detected MIME type

```ruby
validates_spoof_warning :file
```

## IO Adapters

### ZipEntryAdapter

Pass a `Zip::Entry` object directly to Paperclip. The adapter extracts the entry to a tempfile transparently.

```ruby
Zip::File.open('archive.zip') do |zip|
  entry = zip.find_entry('document.pdf')
  model.file = entry
  model.save!
end
```

Requires the `rubyzip` gem.

### CopyAdapter

Used internally by MultipleStorage to duplicate file data between storage backends. No user configuration required.
