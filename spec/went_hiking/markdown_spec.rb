require_relative "../spec_helper"
require "went_hiking/markdown"

RSpec.describe WentHiking::Markdown do
  it "renders markdown and strips unsafe HTML" do
    html = described_class.new.render("[trail](https://example.com)<script>alert(1)</script>")

    expect(html).to include('<a href="https://example.com"')
    expect(html).to include("trail")
    expect(html).not_to include("<script")
  end
end
