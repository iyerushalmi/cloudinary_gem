if RUBY_VERSION > '2.2.2'
  require 'spec_helper'

  AS_TAG = "active_storage_" + SUFFIX
  BASENAME = File.basename(TEST_IMG, '.*')

  CONFIGURATION_PATH = Pathname.new(File.expand_path("service/configurations.yml", __dir__))
  SERVICE = ActiveStorage::Service.configure(:cloudinary, SERVICE_CONFIGURATIONS)

  TEST_IMG_PATH = Pathname.new(TEST_IMG)
  TEST_VIDEO_PATH = Pathname.new(TEST_VIDEO)
  TEST_RAW_PATH = Pathname.new(TEST_RAW)

  describe 'active_storage' do
    let(:key) {ActiveStorage::BlobKey.new({key: SecureRandom.base58(24), filename: BASENAME})}

    before :all do
      @key = ActiveStorage::BlobKey.new key: SecureRandom.base58(24), filename: BASENAME
      @file_key = ActiveStorage::BlobKey.new key: SecureRandom.base58(24), filename: File.basename(TEST_RAW),
                                            content_type: "application/zip"
      @service = self.class.const_get(:SERVICE)
      @service.upload @key, TEST_IMG_PATH, tags: [TEST_TAG, TIMESTAMP_TAG, AS_TAG]
      @service.upload @file_key, TEST_RAW_PATH, tags: [TEST_TAG, TIMESTAMP_TAG, AS_TAG]
    end

    after :all do
      Cloudinary::Api.delete_resources_by_tag AS_TAG
    end

    describe :url_for_direct_upload do
      it "should use the key" do
        key = SecureRandom.base58(24)
        url = @service.url_for_direct_upload(key)
        expect(url).not_to include(BASENAME)
        expect(url).to include("public_id=#{key}")
      end

      it "should include the key in a context field" do
        key = SecureRandom.base58(24)
        url = @service.url_for_direct_upload(key)
        expect(url).to include("context=active_storage_key%3D#{key}")
      end

      it "should not override the key in the context field" do
        key = SecureRandom.base58(24)
        url = @service.url_for_direct_upload(key, context: { active_storage_key: "oops" })
        expect(url).to include("context=active_storage_key%3D#{key}")
      end

      it "should allow the description in a context field" do
        key = SecureRandom.base58(24)
        url = @service.url_for_direct_upload(key, context: { alt: "yes" })
        expect(url).to include("context=alt%3Dyes%7Cactive_storage_key%3D#{key}")
      end

      it "should allow the caption in a context field" do
        key = SecureRandom.base58(24)
        url = @service.url_for_direct_upload(key, context: { caption: "yes" })
        expect(url).to include("context=caption%3Dyes%7Cactive_storage_key%3D#{key}")
      end

      it "should ignore invalid context values" do
        key = SecureRandom.base58(24)
        url = @service.url_for_direct_upload(key, context: nil)
        expect(url).to include("context=active_storage_key%3D#{key}")
      end

      it "should allow other context fields" do
        key = SecureRandom.base58(24)
        url = @service.url_for_direct_upload(key, context: { foo: 123 })
        expect(url).to include("context=foo%3D123%7Cactive_storage_key%3D#{key}")
      end

      it "should allow ActionController::Parameters" do
        key = SecureRandom.base58(24)
        url = @service.url_for_direct_upload(key, context: ActionController::Parameters.new(foo: 123).permit(:foo))
        expect(url).to include("context=foo%3D123%7Cactive_storage_key%3D#{key}")
      end

      it "should include format for raw file" do
        key = ActiveStorage::BlobKey.new key: SecureRandom.base58(24), filename: TEST_RAW
        url = @service.url_for_direct_upload(key, resource_type: "raw")
        expect(url).to include("format=" + File.extname(TEST_RAW).delete('.'))
      end

      it "should set video resource_type for video formats" do
        key = SecureRandom.base58(24)
        types = %w[video/mp4 audio/mp3 application/vnd.apple.mpegurl application/x-mpegurl application/mpegurl]

        types.each do |content_type|

          url = @service.url_for_direct_upload(key, content_type: content_type)

          expect(url).to include("/video/")
        end
      end

      it "should set image resource_type for image formats" do
        key = SecureRandom.base58(24)
        types = %w[application/pdf application/postscript image/*]

        types.each do |content_type|
          url = @service.url_for_direct_upload(key, content_type: content_type)

          expect(url).to include("/image/")
        end
      end

      it "should set raw resource_type for raw formats" do
        key = SecureRandom.base58(24)
        types = %w[text/* application/*]

        types.each do |content_type|
          url = @service.url_for_direct_upload(key, content_type: content_type)

          expect(url).to include("/raw/")
        end
      end

      it "should set image resource_type for other formats" do
        key = SecureRandom.base58(24)
        types = %w[wordprocessingml.document spreadsheetml.sheet]

        types.each do |content_type|
          url = @service.url_for_direct_upload(key, content_type: content_type)

          expect(url).to include("/image/")
        end
      end
    end

    it "should support uploading to Cloudinary" do
      url = @service.url_for_direct_upload(key, tags: [TEST_TAG, TIMESTAMP_TAG, AS_TAG])
      uri = URI.parse url
      request = Net::HTTP::Put.new uri.request_uri
      file = File.open(TEST_IMG)
      request.body_stream = file
      request['content-length'] = file.size
      request['content-type'] = 'image/png'
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request request
      end
      result = Cloudinary::Utils.json_decode(response.body)
      expect(result['error']).not_to be_truthy
      #Same test as uploader_spec "should successfully upload file"
      expect(result["width"]).to eq(TEST_IMG_W)
      expect(result["height"]).to eq(TEST_IMG_H)
      expected_signature = Cloudinary::Utils.api_sign_request({:public_id => result["public_id"], :version => result["version"]}, Cloudinary.config.api_secret)
      expect(result["signature"]).to eq(expected_signature)
    end

    it "should check if resource exists" do
      expect(@service.exist?(@key)).to be_truthy
      expect(@service.exist?(@key + "nonsense")).to be_falsey
    end

    it "should correctly check if a raw file with extension exists" do
      expect(@service.exist?(@file_key)).to be_truthy
    end

    it "should delete a resource" do
      expect(@service.exist?(@key)).to be_truthy
      @service.delete @key
      expect(@service.exist?(@key)).to be_falsey

      expect(@service.exist?(@file_key)).to be_truthy
      @service.delete @file_key
      expect(@service.exist?(@file_key)).to be_falsey
    end

    it "should fail to delete nonexistent key" do
      expect {@service.delete SecureRandom.base58(24)}.not_to raise_error
    end

    it "should support transformations" do
      url = @service.url(@key, crop: 'scale', width: 100)
      expect(url).to match(/c_scale,w_100/)
    end

    it "should use extension from the filename and not from the content-type" do
      @video_key = ActiveStorage::BlobKey.new key: SecureRandom.base58(24), content_type: "video/ogg"
      url = @service.url(@video_key, filename: ActiveStorage::Filename.new(TEST_VIDEO),
                         content_type: "video/ogg")
      expect(url).to end_with("#{@video_key}.mp4")

      @file_key = ActiveStorage::BlobKey.new key: SecureRandom.base58(24), content_type: "application/not-zip"
      url = @service.url(@file_key, filename: ActiveStorage::Filename.new("my_zip.zip"),
                         content_type: "application/not-zip")
      expect(url).to end_with("#{@file_key}.zip")
    end

    it "should fall back to the mime-type based detection when no extension is provided" do
      url = @service.url(@key, filename: ActiveStorage::Filename.new("logo"), content_type: "image/jpeg")
      expect(url).to end_with("#{@key}.jpg")
    end

    it "should not fall back to the mime-type based detection with raw file" do
      @file_key = ActiveStorage::BlobKey.new key: SecureRandom.base58(24), content_type: "application/zip"
      url = @service.url(@file_key, filename: ActiveStorage::Filename.new("my_zip"),
                         content_type: "application/zip")
      expect(url).to end_with(@file_key)
    end

    it "should use correct url for downloading raw file with extension" do
      @file_key = ActiveStorage::BlobKey.new key: SecureRandom.base58(24), content_type: "application/zip",
                                             filename: "my_zip.zip"
      expect(Net::HTTP).to receive(:get_response) do |url|
        expect(url.to_s).to end_with(@file_key + ".zip")
      end.and_return(double.as_null_object)
      @service.download(@file_key)
    end

    it "should use global configuration options" do
      tags = SERVICE_CONFIGURATIONS[:cloudinary][:tags]
      expect(tags).not_to be_empty, "Please set a tags value under cloudinary in #{CONFIGURATION_PATH}"
      expect(Cloudinary::Uploader).to receive(:upload_large).with(TEST_IMG, hash_including(tags: tags))
      @service.upload(key, TEST_IMG, tags: tags)
    end

    it "should use global folder configuration" do
      folder = SERVICE_CONFIGURATIONS[:cloudinary][:folder]
      expect(folder).not_to be_empty, "Please set a folder value under cloudinary in #{CONFIGURATION_PATH}"
      url = @service.url(@key, filename: ActiveStorage::Filename.new("logo"), content_type: "image/jpeg")
      expect(url).to include(folder)
    end

    it "should accept options that override global configuration" do
      tags = SERVICE_CONFIGURATIONS[:cloudinary][:tags]
      expect(tags).not_to be_empty, "Please set a tags value under cloudinary in #{CONFIGURATION_PATH}"
      override_tags = [TEST_TAG, TIMESTAMP_TAG, AS_TAG]
      expect(override_tags).not_to eql(tags), "Overriding tags should be different from configuration"
      expect(Cloudinary::Uploader).to receive(:upload_large).with(TEST_IMG, hash_including(tags: override_tags))
      @service.upload(key, TEST_IMG, tags: override_tags)
    end

    it "should correctly identify resource_type" do
      expect(Cloudinary::Uploader).to receive(:upload_large).with(TEST_IMG_PATH, hash_including(resource_type: 'image'))
      @service.upload(key, TEST_IMG_PATH)

      expect(Cloudinary::Uploader).to receive(:upload_large).with(TEST_VIDEO_PATH, hash_including(resource_type: 'video'))
      @service.upload(key, TEST_VIDEO_PATH)

      expect(Cloudinary::Uploader).to receive(:upload_large).with(TEST_RAW_PATH, hash_including(resource_type: 'raw'))
      @service.upload(key, TEST_RAW_PATH)
    end
  end
end
