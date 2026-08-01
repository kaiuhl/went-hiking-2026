# frozen_string_literal: true

# OAuth 2.1 authorization server tables for rodauth-oauth, used by the MCP
# connector. Client secrets, registration access tokens, and grant tokens are
# stored hashed by rodauth-oauth.
Sequel.migration do
  change do
    create_table(:oauth_applications) do
      primary_key :id
      foreign_key :account_id, :accounts, null: true, on_delete: :cascade
      String :name, null: false
      String :description
      String :scopes, null: false
      String :client_id, null: false, unique: true
      String :client_secret, unique: true
      String :registration_access_token
      String :homepage_url
      String :redirect_uri, null: false, text: true
      String :token_endpoint_auth_method
      String :grant_types
      String :response_types
      String :response_modes
      String :logo_uri
      String :tos_uri
      String :policy_uri
      String :jwks, text: true
      String :jwks_uri
      String :contacts
      String :software_id
      String :software_version
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:oauth_grants) do
      primary_key :id
      foreign_key :account_id, :accounts, null: true, on_delete: :cascade
      foreign_key :oauth_application_id, :oauth_applications, null: false, on_delete: :cascade
      String :type
      String :code
      String :token, unique: true
      String :refresh_token, unique: true
      DateTime :expires_in, null: false
      String :redirect_uri, text: true
      String :scopes, null: false, text: true
      DateTime :revoked_at
      String :code_challenge
      String :code_challenge_method
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :account_id
      index :oauth_application_id
    end
  end
end
