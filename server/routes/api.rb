# frozen_string_literal: true

module ApiRoutes
  def route_api(r)
    r.on "api" do
      r.get "version" do
        json_payload({app: "went-hiking", env: WentHiking.env})
      end

      r.post "markdown-preview" do
        body = request.POST["body"].to_s
        json_payload({html: markdown(body)})
      end
    end
  end
end
