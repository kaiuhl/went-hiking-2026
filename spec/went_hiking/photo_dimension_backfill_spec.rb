require_relative "../spec_helper"
require "went_hiking/photo_dimension_backfill"

RSpec.describe WentHiking::PhotoDimensionBackfill do
  def create_photo(**overrides)
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: account_id, name: "Burnt Lake", slug: "burnt-lake", nights: 0, hiked_at: Time.utc(2026, 5, 1), report_markdown: "", created_at: Time.now, updated_at: Time.now)
    WentHiking::Models::Photo[WentHiking.db[:photos].insert({
      account_id: account_id,
      trip_id: trip_id,
      legacy_image_file_name: "lake.jpg",
      created_at: Time.now,
      updated_at: Time.now
    }.merge(overrides))]
  end

  def create_variant(photo, style:, **overrides)
    WentHiking::Models::PhotoVariant[WentHiking.db[:photo_variants].insert({
      photo_id: photo.id,
      style: style,
      filename: "lake.jpg",
      created_at: Time.now,
      updated_at: Time.now
    }.merge(overrides))]
  end

  def store_jpeg(key, size: "640x480")
    path = WentHiking::Storage.current.path_for(key)
    FileUtils.mkdir_p(File.dirname(path))
    skip "ImageMagick convert is not available" unless system("convert", "-size", size, "gradient:red-blue", path, out: File::NULL, err: File::NULL)
    key
  end

  it "reads the stored file and fills in the dimensions it finds" do
    photo = create_photo
    key = store_jpeg("system/images/#{photo.id}/large/lake.jpg", size: "900x300")
    variant = create_variant(photo, style: "large", s3_key: key)

    result = described_class.call

    expect(result.variants).to eq(1)
    expect(variant.refresh.width).to eq(900)
    expect(variant.height).to eq(300)
  end

  it "gives a photo its own dimensions from the original it was uploaded as" do
    photo = create_photo
    key = store_jpeg("system/images/#{photo.id}/original/lake.jpg", size: "1600x1200")
    create_variant(photo, style: "original", s3_key: key)

    result = described_class.call

    expect(result.photos).to eq(1)
    expect(photo.refresh.width).to eq(1600)
    expect(photo.height).to eq(1200)
  end

  it "leaves legacy rows on the old host alone" do
    photo = create_photo
    variant = create_variant(photo, style: "large", legacy_path: "http://wenthiking.com/system/images/43352/large/lake.jpg")

    result = described_class.call

    expect(result.skipped).to eq(1)
    expect(result.variants).to eq(0)
    expect(variant.refresh.width).to be_nil
  end

  it "counts a row whose file never made it to storage without failing the run" do
    photo = create_photo
    variant = create_variant(photo, style: "large", s3_key: "system/images/#{photo.id}/large/missing.jpg")

    result = described_class.call

    expect(result.missing).to eq(1)
    expect(variant.refresh.width).to be_nil
  end

  it "leaves rows that already know their size untouched" do
    photo = create_photo(width: 800, height: 600)
    key = store_jpeg("system/images/#{photo.id}/large/lake.jpg")
    create_variant(photo, style: "large", s3_key: key, width: 111, height: 222)

    result = described_class.call

    expect(result.variants).to eq(0)
    expect(result.photos).to eq(0)
    expect(photo.variant("large").width).to eq(111)
  end
end
