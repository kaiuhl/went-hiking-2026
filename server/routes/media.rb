# frozen_string_literal: true

module MediaRoutes
  def route_media(r)
    r.on "system" do
      key = "system/#{r.remaining_path.to_s.sub(%r{\A/+}, "")}"
      redirect "#{WentHiking.media_base_url}/#{key}", 302
    end
  end
end
