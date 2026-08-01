# frozen_string_literal: true

# Every listing on the site asks the same question — the most recent published
# trips, in hiked_at order — and until now the only indexes that could help were
# on `status` alone (far too unselective to be worth using: almost every row is
# published) and on `[account_id, hiked_at]`, which needs an account. So the
# planner sorted the whole table for /hikes, for home, and for the top of the
# archive: a full scan and a sort of every trip to return fifty of them.
#
# With `[status, hiked_at]` the same query is a backwards index scan that stops
# after it has enough rows, and paging deeper stays cheap instead of re-sorting
# the archive per page.
Sequel.migration do
  change do
    alter_table(:trips) do
      add_index [:status, :hiked_at], name: :trips_status_hiked_at_index
    end
  end
end
