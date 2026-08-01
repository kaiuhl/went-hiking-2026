require_relative "../spec_helper"
require "went_hiking/pagination"

RSpec.describe WentHiking::Pagination do
  def paginate(page, total, per_page: 50)
    described_class.new(page: page, total: total, per_page: per_page)
  end

  describe "boundaries" do
    it "starts on page one and reports the first slice" do
      pagination = paginate(nil, 8009)

      expect(pagination.page).to eq(1)
      expect(pagination.offset).to eq(0)
      expect(pagination.pages).to eq(161)
      expect(pagination.first?).to be(true)
      expect(pagination.previous_page).to be_nil
      expect(pagination.next_page).to eq(2)
      expect(pagination.first_item).to eq(1)
      expect(pagination.last_item).to eq(50)
    end

    it "reports the last page as a short one" do
      pagination = paginate(161, 8009)

      expect(pagination.offset).to eq(8000)
      expect(pagination.last?).to be(true)
      expect(pagination.next_page).to be_nil
      expect(pagination.previous_page).to eq(160)
      expect(pagination.first_item).to eq(8001)
      expect(pagination.last_item).to eq(8009)
    end

    it "divides evenly without inventing a trailing empty page" do
      expect(paginate(1, 100).pages).to eq(2)
      expect(paginate(1, 101).pages).to eq(3)
      expect(paginate(1, 50).pages).to eq(1)
      expect(paginate(1, 49).pages).to eq(1)
    end

    it "keeps one page and no pager when nothing matches" do
      pagination = paginate(1, 0)

      expect(pagination.pages).to eq(1)
      expect(pagination.multiple_pages?).to be(false)
      expect(pagination.first_item).to eq(0)
      expect(pagination.last_item).to eq(0)
    end
  end

  # Every one of these is something a crawler, a stale bookmark, or a hand-typed
  # URL will ask for. They clamp to the nearest real page rather than 404ing or
  # raising.
  describe "out of range requests" do
    it "clamps below one" do
      expect(paginate(0, 500).page).to eq(1)
      expect(paginate(-7, 500).page).to eq(1)
    end

    it "clamps past the end" do
      expect(paginate(9999, 500).page).to eq(10)
      expect(paginate(11, 500).page).to eq(10)
    end

    it "treats unparseable pages as page one" do
      expect(paginate("cat", 500).page).to eq(1)
      expect(paginate("", 500).page).to eq(1)
      expect(paginate("2fish", 500).page).to eq(2)
    end

    it "clamps to page one when the set is empty" do
      expect(paginate(4, 0).page).to eq(1)
      expect(paginate(4, 0).offset).to eq(0)
    end
  end

  describe "page size" do
    it "honours the requested size" do
      pagination = paginate(3, 500, per_page: 20)

      expect(pagination.per_page).to eq(20)
      expect(pagination.offset).to eq(40)
      expect(pagination.pages).to eq(25)
    end

    it "refuses a size that would be nothing or the whole archive" do
      expect(paginate(1, 500, per_page: 0).per_page).to eq(1)
      expect(paginate(1, 500, per_page: -5).per_page).to eq(1)
      expect(paginate(1, 500, per_page: 10_000).per_page).to eq(described_class::MAX_PER_PAGE)
    end
  end

  describe "page numbers" do
    it "lists every page for a short archive" do
      expect(paginate(1, 300).page_numbers).to eq([1, 2, 3, 4, 5, 6])
    end

    it "elides the middle of a long archive" do
      expect(paginate(80, 8009).page_numbers).to eq([1, :gap, 78, 79, 80, 81, 82, :gap, 161])
    end

    it "does not open a gap of one page" do
      numbers = paginate(4, 8009).page_numbers

      expect(numbers.first(6)).to eq([1, 2, 3, 4, 5, 6])
      expect(numbers).to include(:gap)
      expect(numbers.last).to eq(161)
    end

    it "keeps the ends anchored at either edge of the range" do
      expect(paginate(1, 8009).page_numbers.first).to eq(1)
      expect(paginate(161, 8009).page_numbers.last).to eq(161)
      expect(paginate(161, 8009).page_numbers).to include(159, 160, 161)
    end
  end
end
