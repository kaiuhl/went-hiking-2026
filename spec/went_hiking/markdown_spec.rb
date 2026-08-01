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

  # The page's h1 is the trip's name; a body that opens with "# " used to put a
  # second one halfway down the article, at display size.
  describe "heading levels" do
    it "demotes a leading h1 to an h2" do
      html = described_class.new.render("# UI Audit Test Hike\n\nThe trail was wet.")

      expect(html).to include("<h2>UI Audit Test Hike</h2>")
      expect(html).not_to include("<h1")
    end

    it "demotes a setext h1 as well" do
      expect(described_class.new.render("Basin Lake\n==========\n")).to include("<h2>Basin Lake</h2>")
    end

    it "carries the levels under an h1 down with it rather than flattening them" do
      html = described_class.new.render("# Trip\n\n## Day one\n\n### Morning\n")

      expect(html).to include("<h2>Trip</h2>")
      expect(html).to include("<h3>Day one</h3>")
      expect(html).to include("<h4>Morning</h4>")
    end

    it "stops cascading at the first level nothing is using" do
      html = described_class.new.render("# Trip\n\n## Day one\n\n#### Aside\n")

      expect(html).to include("<h3>Day one</h3>")
      expect(html).to include("<h4>Aside</h4>")
    end

    it "clamps at h6 when every level is taken" do
      html = described_class.new.render("# 1\n\n## 2\n\n### 3\n\n#### 4\n\n##### 5\n\n###### 6\n")

      expect(html).to include("<h6>5</h6>")
      expect(html).to include("<h6>6</h6>")
      expect(html).not_to include("<h7")
    end

    it "leaves a body that already starts at h2 exactly where it is" do
      html = described_class.new.render("## Section\n\n### Detail\n")

      expect(html).to include("<h2>Section</h2>")
      expect(html).to include("<h3>Detail</h3>")
    end

    # A regex over the source would call this a heading and demote the whole
    # report on the strength of a shell comment.
    it "does not count a hash inside a fenced code block" do
      html = described_class.new.render("```sh\n# rm -rf /\n```\n\n## Real heading\n")

      expect(html).to include("<h2>Real heading</h2>")
    end

    it "renders a demotion decided elsewhere so a split report agrees with itself" do
      markdown = described_class.new
      demote_below = described_class.demote_below("# Trip\n\n## Day one\n")

      expect(markdown.render("# Trip\n", demote_below: demote_below)).to include("<h2>Trip</h2>")
      expect(markdown.render("## Day one\n", demote_below: demote_below)).to include("<h3>Day one</h3>")
    end

    it "leaves report_markdown alone" do
      source = "# UI Audit Test Hike\n\nBody.".freeze
      described_class.new.render(source)

      expect(source).to eq("# UI Audit Test Hike\n\nBody.")
    end
  end
end
