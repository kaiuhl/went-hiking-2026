# frozen_string_literal: true

module AccountRoutes
  def route_account(r)
    r.on "account" do
      r.get do
        @account = authenticated_account
        @title = "Your Trail Profile"
        @account_errors = []
        view("accounts/show")
      end

      r.post do
        @account = authenticated_account
        @account_errors = account_form_errors(request.POST)

        if @account_errors.empty?
          @account.update(
            name: request.POST["name"].to_s.strip,
            location: optional_string(request.POST["location"].to_s.strip)
          )
          @account_notice = "Profile saved."
        else
          response.status = 422
        end

        @title = "Your Trail Profile"
        view("accounts/show")
      end
    end
  end

  private

  def account_form_errors(params)
    errors = []
    errors << "Name is required." if params["name"].to_s.strip.empty?
    errors
  end
end
