require_relative "../config/boot"

Que.connection = WentHiking.db
Que.worker_count = Integer(ENV.fetch("QUE_WORKERS", "2"))
Que.start
sleep
