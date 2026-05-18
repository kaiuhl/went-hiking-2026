# frozen_string_literal: true

module PageRoutes
  def route_pages(r)
    r.root do
      @recent_trips = WentHiking::Models::Trip.reverse_order(:hiked_at).limit(12).all
      @title = "Went Hiking"
      view("pages/home")
    end

    r.get "about" do
      @title = "About"
      view("pages/about")
    end

    r.get "privacy_policy" do
      redirect "/privacy"
    end

    r.get "privacy" do
      @title = "Privacy"
      view("pages/privacy")
    end

    r.get "donate" do
      redirect "/about"
    end

    r.get "map" do
      response.status = 410
      @title = "Map Removed"
      view("pages/gone")
    end
  end
end
