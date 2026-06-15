# frozen_string_literal: true

Sequel.migration do
  up do
    from(:photos).where { camera_f_stop <= 0 }.update(camera_f_stop: nil)
  end

  down do
    # Zero f-stops represented missing metadata; do not restore invalid values.
  end
end
