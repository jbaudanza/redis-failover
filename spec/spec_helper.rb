require 'rspec/core'

REDIS_MASTER_PORT = 9010
REDIS_SLAVE_PORT = 9011

def start_master
  start_redis('master', REDIS_MASTER_PORT)
end

def start_slave
  start_redis('slave', REDIS_SLAVE_PORT, "slaveof localhost #{REDIS_MASTER_PORT}")
end

def start_redis(type, port, extra_config=nil)
  #puts "Starting redis #{type}"

  config =<<-EOF
    dbfilename /tmp/redis-#{type}.rdb
    pidfile /tmp/redis-#{type}.pid
    port #{port}
    bind 127.0.0.1
    daemonize yes
    #{extra_config}
  EOF

  process = IO.popen "redis-server -", "a"
  process.puts config
  process.close_write
end

def kill_redis(type)
  pid_file = "/tmp/redis-#{type}.pid"

  return unless File.exists?(pid_file)

  redis_pid = File.read(pid_file)
  if redis_pid
    #puts "Killing redis #{type} #{redis_pid}"
    begin
      Process.kill "TERM", redis_pid.to_i
    rescue Errno::ESRCH # process not found
      FileUtils.rm(REDIS_PID_FILE)
    end
  end
  sleep 1
end

# Starts an EventMachine loop, connects to redis, and runs
# until either redis is no longer processing requests or
# EM::stop_event_loop is called
def run_with_em
  EventMachine::run do
    EM.add_timer(60) do
      puts "Test timed out"
      false.should be_true
    end

    yield

    #   # Poll redis to see if it's finished processing all
    #   # requests
    #   check = lambda {
    #     if ChatChannel.redis.pending_commands?
    #       # It would be nice if there was another way to poll besides next_tick.
    #       # For example, if the redis client had a callback anytime a resposne
    #       # was received
    #       EM::next_tick(&check)
    #     else
    #       EM::stop_event_loop
    #     end
    #   }
    # 
    #   check.call
    # end
  end
end

RSpec.configure do |config|
  # config.before(:all) do
  #   kill_redis
  #   start_redis
  #   $redis = Redis.new(:port => REDIS_PORT)
  # end
  # 
  # config.after(:all) do
  #   kill_redis
  # end
end