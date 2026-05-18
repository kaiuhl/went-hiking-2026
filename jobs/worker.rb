require_relative "../config/boot"
require "went_hiking/photo_variant_job"

Que.connection = WentHiking.db
Que.worker_count = Integer(ENV.fetch("QUE_WORKERS", "2"))
Que.start
sleep
