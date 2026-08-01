require_relative "../spec_helper"

require "went_hiking/storage"

RSpec.describe WentHiking::Storage::Local do
  let(:root) { File.join(WentHiking.root, "tmp/spec-storage") }
  let(:storage) { described_class.new(root) }

  before { FileUtils.rm_rf(root) }
  after { FileUtils.rm_rf(root) }

  def put(key, body = "bytes")
    storage.put(key, io: StringIO.new(body), content_type: "image/jpeg")
  end

  # S3 has no directories, so a deleted key leaves nothing behind. On disk it
  # used to leave the whole tree standing empty.
  it "takes the empty directories with it when a file goes" do
    put("system/images/7/original/lake.jpg")

    storage.delete("system/images/7/original/lake.jpg")

    expect(File.exist?(File.join(root, "system/images/7/original"))).to be(false)
    expect(File.exist?(File.join(root, "system/images/7"))).to be(false)
    expect(File.exist?(File.join(root, "system"))).to be(false)
  end

  it "stops at a directory that still has something in it" do
    put("system/images/7/original/lake.jpg")
    put("system/images/7/large/lake.jpg")

    storage.delete("system/images/7/original/lake.jpg")

    expect(File.exist?(File.join(root, "system/images/7/original"))).to be(false)
    expect(File.exist?(File.join(root, "system/images/7/large/lake.jpg"))).to be(true)
    expect(File.exist?(File.join(root, "system/images/7"))).to be(true)
  end

  it "never climbs past the upload root" do
    put("system/lake.jpg")

    storage.delete("system/lake.jpg")

    expect(File.directory?(root)).to be(true)
    expect(File.directory?(File.dirname(root))).to be(true)
  end

  it "shrugs off a key it would refuse to write" do
    expect { storage.delete("../../etc/passwd") }.not_to raise_error
    expect { storage.delete("system/images/7/original/missing.jpg") }.not_to raise_error
  end
end
