# frozen_string_literal: true

module AccountRoutes
  def route_account(r)
    r.on "account" do
      r.get do
        @account = authenticated_account
        @title = "Your Trail Profile"
        @account_errors = []
        @account_notice = "Profile saved." if request.params["saved"] == "1"
        view("accounts/show")
      end

      r.post do
        @account = authenticated_account
        @account_errors = account_form_errors(request.POST)

        # Post/redirect/get on success, so reloading the confirmation does not
        # ask the browser to resubmit the form. Failures re-render in place,
        # which is what keeps the typed values on screen. #redirect only sets
        # the response, so the render has to sit in the else branch.
        if @account_errors.empty?
          @account.update(
            name: request.POST["name"].to_s.strip,
            location: optional_string(request.POST["location"].to_s.strip)
          )
          redirect "/account?saved=1"
        else
          response.status = 422
          @title = "Your Trail Profile"
          view("accounts/show")
        end
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
