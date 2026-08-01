# frozen_string_literal: true

require "went_hiking/mcp"

module McpRoutes
  def route_mcp(r)
    r.on "mcp" do
      r.is do
        r.post do
          account, scopes = mcp_authorization
          server = WentHiking::Mcp.build_server(account: account, scopes: scopes)
          result = server.handle_json(request.body.read)

          if result.nil?
            response.status = 202
            response["Content-Type"] = "application/json"
            ""
          else
            json_payload_string(result)
          end
        end

        # Stateless Streamable HTTP server: no SSE stream to offer, clients
        # fall back to plain JSON responses.
        r.get do
          request.halt [
            405,
            {"Content-Type" => "application/json", "Allow" => "POST"},
            [JSON.generate({error: "This MCP server is stateless. Send JSON-RPC messages via POST."})]
          ]
        end
      end
    end
  end

  private

  def mcp_authorization
    # Read the bearer token straight from the header rather than via
    # rodauth.authorization_token: that path touches request params, which
    # would make the json_parser plugin consume the JSON-RPC request body.
    scheme, token = request.env["HTTP_AUTHORIZATION"].to_s.split(" ", 2)
    mcp_unauthorized unless scheme&.downcase == "bearer" && !token.to_s.empty?

    grant = rodauth.mcp_grant_for_token(token)
    mcp_unauthorized unless grant

    account_id = grant[:account_id]
    account = account_id && WentHiking::Models::Account[account_id]
    mcp_unauthorized unless account

    scopes = grant[:scopes].to_s.split(" ")
    mcp_unauthorized if (scopes & WentHiking::Mcp::SCOPES).empty?

    [account, scopes]
  end

  def mcp_unauthorized
    metadata_url = "#{WentHiking.public_base_url.to_s.sub(%r{/+\z}, "")}/.well-known/oauth-protected-resource"
    request.halt [
      401,
      {
        "Content-Type" => "application/json",
        "WWW-Authenticate" => %(Bearer realm="went-hiking", resource_metadata="#{metadata_url}")
      },
      [JSON.generate({error: "invalid_token", error_description: "A valid OAuth access token is required."})]
    ]
  end

  def json_payload_string(body, status: 200)
    response.status = status
    response["Content-Type"] = "application/json"
    body
  end
end
