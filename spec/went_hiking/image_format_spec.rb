require_relative "../spec_helper"

require "went_hiking/image_format"

RSpec.describe WentHiking::ImageFormat do
  let(:jpeg) { "\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01".b }
  let(:png) { "\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR".b }
  let(:gif) { "GIF89a\x01\x00\x01\x00\x80\x00\x00".b }
  let(:webp) { "RIFF\x24\x00\x00\x00WEBPVP8 ".b }
  let(:heic) { "\x00\x00\x00\x18ftypheic\x00\x00\x00\x00".b }
  let(:svg) { %(<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>).b }

  describe ".sniff" do
    it "names the format from the leading bytes" do
      expect(described_class.sniff(jpeg)).to eq(:jpeg)
      expect(described_class.sniff(png)).to eq(:png)
      expect(described_class.sniff(gif)).to eq(:gif)
      expect(described_class.sniff(webp)).to eq(:webp)
      expect(described_class.sniff(heic)).to eq(:heic)
    end

    it "refuses to name anything it does not recognise" do
      expect(described_class.sniff(svg)).to be_nil
      expect(described_class.sniff("<html><script>alert(1)</script>")).to be_nil
      expect(described_class.sniff("")).to be_nil
      expect(described_class.sniff(nil)).to be_nil
    end

    it "does not mistake a RIFF container that is not a WebP" do
      expect(described_class.sniff("RIFF\x24\x00\x00\x00WAVEfmt ".b)).to be_nil
    end
  end

  describe ".extension_for" do
    it "normalises every accepted spelling of a type to one extension" do
      expect(described_class.extension_for("image/jpeg")).to eq(".jpg")
      expect(described_class.extension_for("image/pjpeg")).to eq(".jpg")
      expect(described_class.extension_for("IMAGE/JPEG")).to eq(".jpg")
      expect(described_class.extension_for("image/jpeg; charset=binary")).to eq(".jpg")
      expect(described_class.extension_for("image/x-png")).to eq(".png")
      expect(described_class.extension_for("image/gif")).to eq(".gif")
    end

    it "refuses types it does not accept rather than inventing an extension" do
      expect(described_class.extension_for("image/svg+xml")).to be_nil
      expect(described_class.extension_for("text/html")).to be_nil
      expect(described_class.extension_for("")).to be_nil
    end
  end

  describe ".matches?" do
    it "agrees only when the bytes are the type that was declared" do
      expect(described_class.matches?(content_type: "image/jpeg", bytes: jpeg)).to be(true)
      expect(described_class.matches?(content_type: "image/pjpeg", bytes: jpeg)).to be(true)
      expect(described_class.matches?(content_type: "image/png", bytes: jpeg)).to be(false)
    end

    it "rejects SVG bytes wearing an image/jpeg label" do
      expect(described_class.matches?(content_type: "image/jpeg", bytes: svg)).to be(false)
    end

    it "rejects a type it does not accept even when the bytes agree" do
      expect(described_class.matches?(content_type: "image/svg+xml", bytes: svg)).to be(false)
    end
  end

  describe ".io_matches?" do
    it "reads the head of a stream and leaves it rewound" do
      io = StringIO.new(jpeg + ("\x00".b * 64))

      expect(described_class.io_matches?(content_type: "image/jpeg", io: io)).to be(true)
      expect(io.pos).to eq(0)
    end

    it "rejects a stream whose bytes are not the declared type" do
      expect(described_class.io_matches?(content_type: "image/jpeg", io: StringIO.new(svg))).to be(false)
    end
  end
end
