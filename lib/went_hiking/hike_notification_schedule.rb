# frozen_string_literal: true

require "date"
require "tzinfo"

module WentHiking
  module HikeNotificationSchedule
    module_function

    def next_morning_after(now: Time.now)
      timezone = TZInfo::Timezone.get(ENV.fetch("FOLLOW_NOTIFICATION_TIMEZONE", "America/Los_Angeles"))
      hour = Integer(ENV.fetch("FOLLOW_NOTIFICATION_HOUR", "8"))
      local_now = timezone.to_local(now)
      target_date = local_now.to_date + 1

      timezone.local_time(target_date.year, target_date.month, target_date.day, hour, 0, 0).utc
    end
  end
end
