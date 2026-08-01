require_relative "../spec_helper"
require_relative "../../server/roda_app"

# The archive at production scale: eight thousand trips across sixteen years and
# a handful of accounts. Everything here guards a property that only bites once
# the table is big — a listing that costs a query per row, a stats strip that
# loads the archive to count it, a year filter the index cannot serve, a page of
# results with no way to reach the second one.
# Counts the SQL a block issues by hanging a logger off the app's own
# connection. Sequel logs one line per statement at info level.
class QueryCounter
  attr_reader :count

  def initialize
    @count = 0
    @on = false
  end

  def start
    @count = 0
    @on = true
  end

  def stop
    @on = false
    @count
  end

  def info(_message = nil)
    @count += 1 if @on
  end

  %i[debug warn error fatal unknown].each { |level| define_method(level) { |*| nil } }

  def level
    0
  end

  def level=(_value)
    nil
  end

  def info? = true

  def debug? = false

  def warn? = false

  def error? = false

  def fatal? = false
end

RSpec.describe "Archive at scale" do
  include Rack::Test::Methods
  include CsrfHelpers

  def app
    RodaApp.app
  end

  def count_queries
    counter = QueryCounter.new
    WentHiking.db.loggers << counter
    counter.start
    yield
    counter.stop
  ensure
    WentHiking.db.loggers.delete(counter)
  end

  def create_account(name:, email: nil, location: nil)
    WentHiking.db[:accounts].insert(
      email: email || "#{name.downcase.gsub(/\W+/, "-")}@example.com",
      name: name,
      slug: name.downcase.gsub(/\W+/, "-"),
      status_id: 2,
      location: location,
      created_at: Time.now,
      updated_at: Time.now
    )
  end

  def create_trip(account_id:, name:, hiked_at:, mileage: nil, nights: 0, elevation: nil, status: "published")
    WentHiking.db[:trips].insert(
      account_id: account_id,
      name: name,
      slug: name.downcase.gsub(/\W+/, "-"),
      nights: nights,
      mileage: mileage,
      elevation: elevation,
      hiked_at: hiked_at,
      status: status,
      created_at: Time.now,
      updated_at: Time.now
    )
  end

  def create_photo(account_id:, trip_id:, index: 0)
    filename = "shot-#{trip_id}-#{index}.jpg"
    photo_id = WentHiking.db[:photos].insert(
      account_id: account_id,
      trip_id: trip_id,
      legacy_image_file_name: filename,
      width: 3000,
      height: 2000,
      taken_at: Time.utc(2024, 6, 1, 9 + index),
      caption: "Frame #{index}",
      created_at: Time.now,
      updated_at: Time.now
    )
    %w[original large medium].each do |style|
      WentHiking.db[:photo_variants].insert(
        photo_id: photo_id,
        style: style,
        filename: filename,
        s3_key: "system/images/#{photo_id}/#{style}/#{filename}",
        width: 900,
        height: 600,
        created_at: Time.now,
        updated_at: Time.now
      )
    end
    photo_id
  end

  # ---------------------------------------------------------------------------

  describe "archive stats" do
    # The strip used to be built by loading every published trip — report bodies
    # and all — to produce three numbers. The aggregate has to agree with that
    # sum exactly, floats included, or the front page quietly changes.
    it "renders the same totals the row-by-row sum produced" do
      account_id = create_account(name: "Kai")
      mileages = [8.5, 12.25, nil, 3.1, 0.0, 27.4, 6.75]
      nights = [0, 2, 1, 0, 0, 3, 0]
      mileages.each_with_index do |mileage, index|
        create_trip(
          account_id: account_id,
          name: "Trip #{index}",
          hiked_at: Time.utc(2024, 1 + index, 5),
          mileage: mileage,
          nights: nights[index]
        )
      end
      # A draft and its photo are outside the archive and must not be counted.
      draft_id = create_trip(account_id: account_id, name: "Draft Ridge", hiked_at: Time.utc(2024, 9, 1), mileage: 99.0, nights: 9, status: "draft")
      create_photo(account_id: account_id, trip_id: draft_id)
      published = WentHiking.db[:trips].where(status: "published").select_map(:id)
      published.first(3).each_with_index { |trip_id, index| create_photo(account_id: account_id, trip_id: trip_id, index: index) }

      expected = WentHiking::Models::Trip.published.all
      expected_trips = expected.size
      expected_miles = expected.sum { |trip| trip.mileage.to_f }
      expected_nights = expected.sum { |trip| trip.nights.to_i }

      stats = WentHiking::Models::Trip.published.totals

      expect(stats[:trips]).to eq(expected_trips)
      expect(stats[:miles]).to eq(expected_miles)
      expect(stats[:nights]).to eq(expected_nights)

      get "/"

      # Rendered through the app's own formatter from the row-by-row sum, so
      # this compares the printed numbers rather than a hand-typed guess at them.
      formatter = Object.new.extend(ViewHelpers)

      expect(last_response).to be_ok
      expect(last_response.body).to include("#{expected_trips} trips")
      expect(last_response.body).to include("3 photos")
      expect(last_response.body).to include("#{formatter.format_number(expected_miles, precision: 1)} miles logged")
      expect(last_response.body).to include("#{expected_nights} nights out")
    end

    it "answers zero for an empty archive instead of nil" do
      stats = WentHiking::Models::Trip.published.totals

      expect(stats).to eq(trips: 0, miles: 0.0, nights: 0)
    end

    it "counts the archive without loading it" do
      account_id = create_account(name: "Kai")
      12.times { |index| create_trip(account_id: account_id, name: "Trip #{index}", hiked_at: Time.utc(2024, 1, 1 + index), mileage: 4.0, nights: 1) }

      expect(count_queries { WentHiking::Models::Trip.published.totals }).to eq(1)
    end
  end

  # ---------------------------------------------------------------------------

  describe "year filter" do
    it "asks the database for a range, not for a function of the column" do
      sql = WentHiking::Models::Trip.published.in_year(2023).sql

      # A bare column on the left is the whole point: EXTRACT(year FROM hiked_at)
      # cannot use trips_account_id_hiked_at_index, a range predicate can.
      expect(sql).not_to match(/extract/i)
      expect(sql).to include("hiked_at")
      expect(sql).to include(">=")
      expect(sql).to include("<")
    end

    it "returns exactly the trips whose hiked_at falls in that year" do
      account_id = create_account(name: "Kai")
      stamps = [
        Time.utc(2022, 12, 31, 23, 59, 59),
        Time.utc(2023, 1, 1, 0, 0, 0),
        Time.utc(2023, 6, 15, 12, 0, 0),
        Time.utc(2023, 12, 31, 23, 59, 59),
        Time.utc(2024, 1, 1, 0, 0, 0)
      ]
      stamps.each_with_index { |stamp, index| create_trip(account_id: account_id, name: "Trip #{index}", hiked_at: stamp) }

      in_year = WentHiking::Models::Trip.published.in_year(2023).order(:hiked_at).all
      by_hand = WentHiking::Models::Trip.published.all.select { |trip| trip.hiked_at.year == 2023 }.sort_by(&:hiked_at)

      expect(in_year.map(&:id)).to eq(by_hand.map(&:id))
      expect(in_year.map(&:name)).to eq(["Trip 1", "Trip 2", "Trip 3"])
    end

    it "keeps a profile year showing the same hikes it always did" do
      account_id = create_account(name: "Kai")
      create_trip(account_id: account_id, name: "In Year", hiked_at: Time.utc(2023, 5, 4))
      create_trip(account_id: account_id, name: "Next Year", hiked_at: Time.utc(2024, 5, 4))

      get "/people/#{account_id}-kai?year=2023"

      expect(last_response).to be_ok
      expect(last_response.body).to include("In Year")
      expect(last_response.body).not_to include(">Next Year<")
      expect(last_response.body).to include("1 trip")
      expect(last_response.body).to include("in 2023")
    end
  end

  # ---------------------------------------------------------------------------

  describe "trip list query cost" do
    # The regression guard. Before eager loading, this listing cost three queries
    # a row plus three per photo; the number below must not move when rows are
    # added, only when the shape of the page changes.
    it "costs the same number of queries however many rows are on the page" do
      account_id = create_account(name: "Kai")
      other_id = create_account(name: "Jen")

      seed = lambda do |count, offset|
        count.times do |index|
          trip_id = create_trip(
            account_id: index.even? ? account_id : other_id,
            name: "Trip #{offset + index}",
            hiked_at: Time.utc(2024, 1 + ((offset + index) % 12), 1 + ((offset + index) % 28)),
            mileage: 5.5,
            nights: index % 3
          )
          2.times { |n| create_photo(account_id: account_id, trip_id: trip_id, index: n) }
          WentHiking.db[:hearts].insert(account_id: other_id, trip_id: trip_id, created_at: Time.now, updated_at: Time.now)
        end
      end

      seed.call(5, 0)
      get "/hikes"
      expect(last_response).to be_ok
      small = count_queries { get "/hikes" }

      seed.call(25, 5)
      get "/hikes"
      expect(last_response).to be_ok
      large = count_queries { get "/hikes" }

      expect(WentHiking.db[:trips].count).to eq(30)
      expect(large).to eq(small)
      expect(large).to be < 15
    end

    it "keeps home and a profile bounded too" do
      account_id = create_account(name: "Kai")
      30.times do |index|
        trip_id = create_trip(account_id: account_id, name: "Trip #{index}", hiked_at: Time.utc(2024, 1 + (index % 12), 1 + (index % 28)), mileage: 3.0)
        create_photo(account_id: account_id, trip_id: trip_id)
      end

      get "/"
      get "/people/#{account_id}-kai"

      expect(count_queries { get "/" }).to be < 20
      expect(count_queries { get "/people/#{account_id}-kai" }).to be < 20
    end
  end

  # ---------------------------------------------------------------------------

  describe "pagination" do
    def seed_archive(count)
      account_id = create_account(name: "Kai")
      count.times do |index|
        create_trip(
          account_id: account_id,
          name: "Hike #{format("%03d", index)}",
          # Descending hiked_at so "Hike 000" is newest and lands on page one.
          hiked_at: Time.utc(2024, 1, 1) - (index * 86_400),
          mileage: 4.0
        )
      end
      account_id
    end

    it "splits the archive into pages of fifty with real links" do
      seed_archive(120)

      get "/hikes"

      expect(last_response).to be_ok
      expect(last_response.body.scan('class="trip-row-link"').size).to eq(50)
      expect(last_response.body).to include("120 hikes")
      expect(last_response.body).to include('href="/hikes?page=2"')
      expect(last_response.body).to include("Showing 1&ndash;50 of 120 hikes")
      expect(last_response.body).to include('<span class="pager-step is-disabled">Previous</span>')
      expect(last_response.body).to include("Hike 000")
      expect(last_response.body).not_to include("Hike 050")
    end

    it "walks to the middle of the archive" do
      seed_archive(120)

      get "/hikes?page=2"

      expect(last_response).to be_ok
      expect(last_response.body).to include("Hike 050")
      expect(last_response.body).not_to include("Hike 000<")
      expect(last_response.body).to include("Showing 51&ndash;100 of 120 hikes")
      # Page one is the bare path, so the archive has one canonical first page.
      expect(last_response.body).to include('href="/hikes" rel="prev"')
      expect(last_response.body).to include('href="/hikes?page=3" rel="next"')
    end

    it "ends the run without a dead Next" do
      seed_archive(120)

      get "/hikes?page=3"

      expect(last_response).to be_ok
      expect(last_response.body).to include("Showing 101&ndash;120 of 120 hikes")
      expect(last_response.body).to include('<span class="pager-step is-disabled">Next</span>')
      expect(last_response.body.scan('class="trip-row-link"').size).to eq(20)
    end

    it "clamps a page past the end instead of erroring" do
      seed_archive(120)

      get "/hikes?page=9999"

      expect(last_response).to be_ok
      expect(last_response.body).to include("Showing 101&ndash;120 of 120 hikes")
    end

    it "clamps zero, negative, and unparseable pages to the first" do
      seed_archive(120)

      ["0", "-4", "cat", ""].each do |page|
        get "/hikes?page=#{page}"

        expect(last_response).to be_ok, "page=#{page.inspect} returned #{last_response.status}"
        expect(last_response.body).to include("Showing 1&ndash;50 of 120 hikes")
      end
    end

    it "shows no pager at all when everything fits on one page" do
      seed_archive(12)

      get "/hikes"

      expect(last_response).to be_ok
      expect(last_response.body).to include("12 hikes")
      expect(last_response.body).not_to include('class="pager"')
    end

    it "states the true match count on a search and carries the query across pages" do
      account_id = create_account(name: "Kai")
      70.times { |index| create_trip(account_id: account_id, name: "Ridge Walk #{format("%03d", index)}", hiked_at: Time.utc(2024, 1, 1) - (index * 86_400)) }
      create_trip(account_id: account_id, name: "Lake Basin", hiked_at: Time.utc(2020, 1, 1))

      get "/search?q=ridge"

      expect(last_response).to be_ok
      expect(last_response.body).to include("70 hikes match")
      expect(last_response.body).to include('href="/search?q=ridge&amp;page=2"')
      expect(last_response.body).not_to include("Lake Basin")

      get "/search?q=ridge&page=2"

      expect(last_response).to be_ok
      expect(last_response.body).to include("Showing 51&ndash;70 of 70 hikes")
    end

    it "paginates a heavy profile year and keeps the year in the links" do
      account_id = create_account(name: "Kai")
      60.times { |index| create_trip(account_id: account_id, name: "Year Hike #{format("%03d", index)}", hiked_at: Time.utc(2023, 12, 31) - (index * 86_400), mileage: 2.0) }

      get "/people/#{account_id}-kai?year=2023"

      expect(last_response).to be_ok
      expect(last_response.body.scan('class="trip-row-link"').size).to eq(50)
      # The header counts the year, not the page.
      expect(last_response.body).to include("60 trips")
      expect(last_response.body).to include("120 miles logged")
      expect(last_response.body).to include("Showing 1&ndash;50 of 60 hikes")
      expect(last_response.body).to include("year=2023&amp;page=2")

      get "/people/#{account_id}-kai?year=2023&page=2"

      expect(last_response).to be_ok
      expect(last_response.body.scan('class="trip-row-link"').size).to eq(10)
      expect(last_response.body).to include("60 trips")
    end
  end

  # ---------------------------------------------------------------------------

  describe "members index" do
    it "lists hikers with their published trip counts, busiest first" do
      kai = create_account(name: "Kai", location: "Portland, Oregon")
      jen = create_account(name: "Jen")
      create_account(name: "Newcomer")

      3.times { |index| create_trip(account_id: kai, name: "Kai Trip #{index}", hiked_at: Time.utc(2024, 1, 1 + index)) }
      create_trip(account_id: jen, name: "Jen Trip", hiked_at: Time.utc(2024, 2, 1))
      create_trip(account_id: jen, name: "Jen Draft", hiked_at: Time.utc(2024, 2, 2), status: "draft")

      get "/people"

      expect(last_response).to be_ok
      expect(last_response.body).to include("Hikers")
      expect(last_response.body).to include("3 hikers")
      expect(last_response.body).to include("href=\"/people/#{kai}-kai\"")
      expect(last_response.body).to include("href=\"/people/#{jen}-jen\"")
      expect(last_response.body).to include("3 hikes")
      # Drafts are not part of anyone's public count.
      expect(last_response.body).to include("1 hike<")
      expect(last_response.body).to include("0 hikes")
      expect(last_response.body).to include("Portland, Oregon")
      expect(last_response.body.index("Kai")).to be < last_response.body.index("Newcomer")
    end

    it "paginates and clamps like the rest of the archive" do
      50.times { |index| create_account(name: "Hiker #{format("%03d", index)}") }

      get "/people"

      expect(last_response).to be_ok
      expect(last_response.body.scan('class="member-index-link"').size).to eq(40)
      expect(last_response.body).to include("Showing 1&ndash;40 of 50 hikers")
      expect(last_response.body).to include('href="/people?page=2"')

      get "/people?page=987"

      expect(last_response).to be_ok
      expect(last_response.body.scan('class="member-index-link"').size).to eq(10)
      expect(last_response.body).to include("Showing 41&ndash;50 of 50 hikers")
    end

    it "costs a fixed number of queries however many members there are" do
      5.times { |index| create_account(name: "Hiker #{index}") }
      get "/people"
      small = count_queries { get "/people" }

      35.times { |index| create_account(name: "Later Hiker #{index}") }
      get "/people"
      large = count_queries { get "/people" }

      expect(large).to eq(small)
      expect(large).to be < 10
    end

    it "says so plainly when there are no members yet" do
      get "/people"

      expect(last_response).to be_ok
      expect(last_response.body).to include("No hikers yet.")
      expect(last_response.body).not_to include('class="pager"')
    end
  end
end
