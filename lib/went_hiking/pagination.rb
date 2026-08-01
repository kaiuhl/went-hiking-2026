# frozen_string_literal: true

module WentHiking
  # Offset paging for the archive listings. The count comes from the caller —
  # always a `COUNT(*)`, never a loaded page of rows — and everything else here
  # is arithmetic.
  #
  # Out-of-range pages clamp rather than 404. "?page=0", "?page=-3", "?page=cat"
  # and "?page=9999" are all things a crawler or a stale link will ask for, and
  # every one of them has an obvious sane answer; a 404 on a page that plainly
  # exists in spirit only teaches search engines that the archive is broken.
  class Pagination
    DEFAULT_PER_PAGE = 50
    MAX_PER_PAGE = 200
    # Pages either side of the current one that get a numbered link.
    WINDOW = 2

    attr_reader :per_page, :total, :page

    def initialize(page:, total:, per_page: DEFAULT_PER_PAGE)
      @per_page = per_page.to_i.clamp(1, MAX_PER_PAGE)
      @total = [total.to_i, 0].max
      @page = self.class.requested_page(page).clamp(1, pages)
    end

    # "3" and "3abc" and nil all have to land somewhere; String#to_i already
    # answers 3, 3, and 0, and the clamp above turns the 0 into page one.
    def self.requested_page(value)
      value.to_s.strip.to_i
    end

    def pages
      return 1 if total.zero?

      ((total - 1) / per_page) + 1
    end

    def offset
      (page - 1) * per_page
    end

    def multiple_pages?
      pages > 1
    end

    def first?
      page <= 1
    end

    def last?
      page >= pages
    end

    def previous_page
      first? ? nil : page - 1
    end

    def next_page
      last? ? nil : page + 1
    end

    # 1 … 4 5 [6] 7 8 … 161, with :gap standing in for each elision. Small
    # archives skip the elisions entirely and just list every page.
    def page_numbers
      return (1..pages).to_a if pages <= (WINDOW * 2) + 3

      wanted = ([1, pages] + ((page - WINDOW)..(page + WINDOW)).to_a)
        .select { |number| number.between?(1, pages) }
        .uniq
        .sort

      wanted.each_with_object([]) do |number, memo|
        memo << :gap if memo.last.is_a?(Integer) && number > memo.last + 1
        memo << number
      end
    end

    # The first and last row numbers on this page, 1-indexed, for "51-100 of 8,009".
    def first_item
      total.zero? ? 0 : offset + 1
    end

    def last_item
      [offset + per_page, total].min
    end
  end
end
