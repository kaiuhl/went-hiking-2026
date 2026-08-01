# MCP Connector

Went Hiking hosts a remote MCP server so members can post hikes from Claude or
ChatGPT — "post my trip to the Goat Rocks to went hiking" from a phone works
end to end: draft the hike in chat, tap a link to add photos from the camera
roll, iterate on the report, then confirm and publish.

## Endpoints

| Path | What |
| --- | --- |
| `POST /mcp` | MCP Streamable HTTP endpoint (stateless, JSON responses, no SSE) |
| `/.well-known/oauth-protected-resource` | RFC 9728 resource metadata (also served with `/mcp` suffix) |
| `/.well-known/oauth-authorization-server` | RFC 8414 authorization server metadata |
| `POST /register` | RFC 7591 dynamic client registration (open; clients are public + PKCE) |
| `GET/POST /authorize` | Consent page (`server/views/authorize.erb`), member must be logged in |
| `POST /token` | Code + refresh token exchange |
| `POST /revoke` | RFC 7009 token revocation |
| `GET /hikes/:slug/photos/mobile-upload?token=…` | Signed phone upload page, no session needed |

OAuth is implemented with `rodauth-oauth` inside the existing Rodauth block
(`server/roda_app.rb`): authorization code grant + PKCE (S256, required),
dynamic client registration, token revocation. Access tokens last 60 minutes,
refresh tokens rotate. Scopes are `hikes:read` and `hikes:write`. Tables live
in `db/migrations/006_oauth.rb`; tokens and client secrets are stored hashed.

## Tools

Defined in `lib/went_hiking/mcp/tools.rb`, served per-request by
`server/routes/mcp.rb` with the token's account as the actor:

- `list_my_hikes` / `get_hike` — read-only, include private drafts, full report
  markdown and photo metadata (useful for matching the member's writing voice).
- `create_hike_draft` — always creates a draft; returns a photo upload link.
- `update_hike` — partial updates; draft renames also refresh the slug.
- `set_photo_caption` — set/clear one caption.
- `get_photo_upload_link` — fresh signed upload link (~2 h TTL).
- `publish_hike` — flips draft → published, schedules follower emails via
  `HikeNotificationScheduler`. The description instructs assistants to confirm
  with the member first; drafts named "Untitled Hike" are refused.

## Phone photo uploads

Binary uploads can't ride through tool calls, so `create_hike_draft` and
`get_photo_upload_link` mint an HMAC-signed, expiring token
(`lib/went_hiking/upload_tokens.rb`) embedded in a link to the mobile upload
page. The page reuses the existing direct-to-S3 presigned POST flow (falling
back to classic multipart upload where direct upload is unavailable, e.g.
local storage in development). The photo endpoints in `server/routes/hikes.rb`
accept either the owner's session or a valid `upload_token`.

## Connecting a client

- **Claude**: claude.ai → Settings → Connectors → Add custom connector →
  `https://wenthiking.com/mcp`. Available on all plans (Free is limited to one
  custom connector); once added on the web it syncs to the iOS/Android apps and
  Claude Desktop. Claude registers itself via DCR and walks the member through
  login + consent.
- **ChatGPT**: Settings → Apps & Connectors (developer mode may need to be
  enabled) → add the same URL. ChatGPT requires OAuth 2.1 + DCR, which this
  server provides.

## Development notes

- No new required env vars. `UPLOAD_TOKEN_SECRET` optionally overrides the
  upload-link secret; it falls back to `RODAUTH_HMAC_SECRET` / `SESSION_SECRET`.
- Non-production allows `http://` redirect URIs so MCP Inspector
  (`npx @modelcontextprotocol/inspector`) can run the full OAuth flow against
  `http://localhost:9292/mcp`.
- Run the migration before booting: the rodauth-oauth feature inspects the
  `oauth_grants` table at app load.
- Specs: `spec/server/mcp_spec.rb` covers discovery, the full
  register → consent → PKCE → token → refresh dance, the MCP handshake, every
  tool (including ownership and scope enforcement), and the upload-token page.
- Revoking a connection today means deleting rows from `oauth_grants` (or the
  client's row in `oauth_applications`); an account-settings UI for this is a
  sensible follow-up.
