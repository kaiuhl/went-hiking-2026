workers Integer(ENV.fetch("WEB_CONCURRENCY", "0"))
threads_count = Integer(ENV.fetch("RAILS_MAX_THREADS", ENV.fetch("PUMA_THREADS", "5")))
threads threads_count, threads_count

port ENV.fetch("PORT", "9292")
environment ENV.fetch("APP_ENV", ENV.fetch("RACK_ENV", "development"))

plugin :tmp_restart
