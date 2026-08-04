require_relative "../spec_helper"

require "vips"
require "went_hiking/avatar_upload"
require "went_hiking/models"

RSpec.describe WentHiking::AvatarUpload do
  def create_account(legacy_user_id: nil)
    id = WentHiking.db[:accounts].insert(
      email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2,
      legacy_user_id: legacy_user_id, created_at: Time.now, updated_at: Time.now
    )
    WentHiking::Models::Account[id]
  end

  def upload_for(path, filename: File.basename(path), type: "image/jpeg")
    tempfile = Tempfile.new(["avatar-upload", File.extname(filename)])
    tempfile.binmode
    tempfile.write(File.binread(path))
    tempfile.rewind
    {filename: filename, type: type, tempfile: tempfile}
  end

  def jpeg_fixture(width: 800, height: 600, name: "trail-selfie.jpg")
    path = File.join(ENV.fetch("LOCAL_UPLOAD_ROOT"), "fixtures", name)
    FileUtils.mkdir_p(File.dirname(path))
    Vips::Image.gaussnoise(width, height).jpegsave(path)
    path
  end

  def stored_path(key)
    File.join(ENV.fetch("LOCAL_UPLOAD_ROOT"), key)
  end

  it "stores square JPEG variants sized for every place an avatar renders" do
    account = create_account

    result = described_class.new(account: account, upload: upload_for(jpeg_fixture(width: 1600, height: 900))).call

    expect(result).to be_success
    account.refresh
    expect(account.avatar_file_name).to eq("trail-selfie.jpg")
    expect(account.avatar_content_type).to eq("image/jpeg")
    expect(account.avatar_file_size).to be > 0

    sizes = {"original" => [1200, 675], "medium" => [300, 300], "thumbnail" => [125, 125], "micro" => [72, 72]}
    sizes.each do |style, (width, height)|
      image = Vips::Image.new_from_file(stored_path("system/avatars/#{account.id}/#{style}/trail-selfie.jpg"))
      expect([image.width, image.height]).to eq([width, height]), "#{style} should be #{width}x#{height}"
    end
  end

  it "transcodes PNG uploads to JPEG so the stored name matches every derived key" do
    account = create_account
    path = File.join(ENV.fetch("LOCAL_UPLOAD_ROOT"), "fixtures", "portrait.png")
    FileUtils.mkdir_p(File.dirname(path))
    Vips::Image.gaussnoise(400, 400).pngsave(path)

    result = described_class.new(account: account, upload: upload_for(path, type: "image/png")).call

    expect(result).to be_success
    expect(account.refresh.avatar_file_name).to eq("portrait.jpg")
    expect(File.exist?(stored_path("system/avatars/#{account.id}/micro/portrait.jpg"))).to be(true)
  end

  it "writes an imported member's new avatar where avatar_url reads it" do
    account = create_account(legacy_user_id: 51)

    result = described_class.new(account: account, upload: upload_for(jpeg_fixture)).call

    expect(result).to be_success
    expect(File.exist?(stored_path("system/avatars/51/medium/trail-selfie.jpg"))).to be(true)
    expect(File.exist?(stored_path("system/avatars/#{account.id}/medium/trail-selfie.jpg"))).to be(false)
  end

  it "deletes the replaced avatar's files when the new one lands under a different name" do
    account = create_account
    described_class.new(account: account, upload: upload_for(jpeg_fixture(name: "before.jpg"))).call
    expect(File.exist?(stored_path("system/avatars/#{account.id}/medium/before.jpg"))).to be(true)

    described_class.new(account: account, upload: upload_for(jpeg_fixture(name: "after.jpg"))).call

    expect(File.exist?(stored_path("system/avatars/#{account.id}/medium/after.jpg"))).to be(true)
    expect(File.exist?(stored_path("system/avatars/#{account.id}/medium/before.jpg"))).to be(false)
    expect(account.refresh.avatar_file_name).to eq("after.jpg")
  end

  it "rejects files whose bytes are not an accepted image, whatever the browser claimed" do
    account = create_account
    path = File.join(ENV.fetch("LOCAL_UPLOAD_ROOT"), "fixtures", "notes.jpg")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "definitely not a picture" * 100)

    upload = upload_for(path, type: "image/jpeg")
    result = described_class.new(account: account, upload: upload).call

    expect(result).not_to be_success
    expect(result.errors).to include("Profile photos must be JPEG, PNG, or GIF.")
    expect(account.refresh.avatar_file_name).to be_nil
    expect(Dir.exist?(File.join(ENV.fetch("LOCAL_UPLOAD_ROOT"), "system"))).to be(false)
  end

  it "rejects oversized files before decoding anything" do
    account = create_account
    path = File.join(ENV.fetch("LOCAL_UPLOAD_ROOT"), "fixtures", "huge.jpg")
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, "\xFF\xD8\xFF".b + ("\0".b * (described_class::MAX_BYTES + 1)))

    result = described_class.new(account: account, upload: upload_for(path)).call

    expect(result.errors).to include("Profile photos must be 5 MB or smaller.")
  end

  it "reports a decode failure as an error instead of half-saving" do
    account = create_account
    path = File.join(ENV.fetch("LOCAL_UPLOAD_ROOT"), "fixtures", "truncated.jpg")
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, "\xFF\xD8\xFF".b + ("\0".b * 4096))

    result = described_class.new(account: account, upload: upload_for(path)).call

    expect(result).not_to be_success
    expect(result.errors.join).to include("could not be read")
    expect(account.refresh.avatar_file_name).to be_nil
  end

  it "removes the stored avatar and its files" do
    account = create_account
    described_class.new(account: account, upload: upload_for(jpeg_fixture)).call

    described_class.remove(account)

    account.refresh
    expect(account.avatar_file_name).to be_nil
    expect(account.avatar_content_type).to be_nil
    expect(account.avatar_file_size).to be_nil
    expect(Dir.exist?(File.join(ENV.fetch("LOCAL_UPLOAD_ROOT"), "system/avatars/#{account.id}"))).to be(false)
  end

  it "treats a missing upload as absent rather than an error" do
    expect(described_class.present?(nil)).to be(false)
    expect(described_class.present?("")).to be(false)
    expect(described_class.new(account: create_account, upload: nil).call).to be_success
  end
end
