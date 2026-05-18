# frozen_string_literal: true

require "que"

Sequel.migration do
  up do
    next unless database_type == :postgres

    Que.connection = self
    Que.migrate!(version: 7)
  end

  down do
    next unless database_type == :postgres

    Que.connection = self
    Que.migrate!(version: 0)
  end
end
