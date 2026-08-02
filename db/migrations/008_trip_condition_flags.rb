# frozen_string_literal: true

# Optional per-hike condition flags. NULL means the author didn't say, which
# is a different fact from "none" — an author tapping "none" is asserting no
# mosquitoes, and both facts matter to a future conditions search. Allowed
# values live in WentHiking::HikeFlags.
Sequel.migration do
  change do
    alter_table(:trips) do
      add_column :beauty, String
      add_column :mosquitoes, String
      add_column :wildflowers, String
      add_column :swimming, String
      add_column :snow, String
      add_column :crowds, String
    end
  end
end
