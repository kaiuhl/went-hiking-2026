require_relative "../spec_helper"
require "went_hiking/markdown"

RSpec.describe WentHiking::Markdown do
  it "renders markdown and strips unsafe HTML" do
    html = described_class.new.render("[trail](https://example.com)<script>alert(1)</script>")

    expect(html).to include('<a href="https://example.com"')
    expect(html).to include("trail")
    expect(html).not_to include("<script")
  end

  # Stripping the tag and keeping the text used to publish a stylesheet, or the
  # body of a script, as visible prose in the middle of a trip report.
  it "removes what is inside a style or script rather than printing it" do
    html = described_class.new.render(<<~MARKDOWN)
      Before

      <style>body{display:none}</style>

      <script>alert("pwned")</script>

      After
    MARKDOWN

    expect(html).to include("Before")
    expect(html).to include("After")
    expect(html).not_to include("display:none")
    expect(html).not_to include("pwned")
  end

  it "removes an unclosed script to the end of the report" do
    html = described_class.new.render("Before\n\n<script>alert(\"pwned\")")

    expect(html).to include("Before")
    expect(html).not_to include("pwned")
  end

  it "removes attributes and casing variations too" do
    html = described_class.new.render(%(<STYLE type="text/css" media="all">body{display:none}</STYLE>))

    expect(html).not_to include("display:none")
    expect(html).not_to include("text/css")
  end

  it "still removes the contents when one survives as an element" do
    html = Sanitize.fragment("<p>Keep</p><style>body{display:none}</style>", described_class::SANITIZE_CONFIG)

    expect(html).to include("Keep")
    expect(html).not_to include("display:none")
  end
end
