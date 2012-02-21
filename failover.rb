require 'eventmachine'
require 'em-hiredis'
require 'socket'
require 'logger'

class Failover
  attr_accessor :logger

  def initialize(options={})
    @options = {
      :on_failure => lambda{}
    }.merge(options)

    raise ArgumentError("onconnect option required") unless @options[:master]
    raise ArgumentError("master option required") unless @options[:master]
    raise ArgumentError("slave option required") unless @options[:master]

    if !@options[:logger]
      @options[:logger] = Logger.new(STDERR)
    end

    connect
  end

  def logger
    @options[:logger]
  end

  def on_slave_connect_failure
    callback(:on_connect, @options[:master])
  end

  def connect
    @master = EM::Hiredis.connect(@options[:master])
    @slave = EM::Hiredis.connect(@options[:slave])
    @subscriber = EM::Hiredis.connect(@options[:slave])

    # XXX: Pick a better timeout value
    connection_timeout = EM.add_timer(1) do |result|
      puts "Timeout!"
      # XXX: Disconnect redis socket
    end

    @slave.incr('failover:clients:id') do |result|
      @client_id = result

      EM.cancel_timer(connection_timeout)

      @slave.info do |result|
        # XXX Handle the case where the slave is down but the master is up
        # XXX verify that the slave is connected to the right master
        # puts result[:master_host]
        # puts result[:master_port]

        if result[:role] == 'master'
          logger.warn("Slave has previously been promoted to master.")
          callback(:on_connect, @options[:slave])
        else
          if @master.host == result[:master_host] &&
             @master.port == result[:master_port].to_i

            @slave.del 'failover:promoted_at'
            schedule_ping
            schedule_health_check

            callback(:on_connect, @options[:master])
          else
            logger.warn(
                "Expected slave to be connected to #{@options[:master]}, " +
                "but instead is #{result[:master_host]}:#{result[:master_port]}")

            on_slave_connect_failure
          end
        end
      end
    end

    @subscriber.subscribe 'failover:promoted'

    @subscriber.on(:message) do |result, param|
      logger.warn("MASTER host failed. SLAVE promoted by #{param}")
      callback(:on_connect, @options[:slave])
    end
  end

  private

  def callback(symbol, *args)
    if @options[symbol]
      @options[symbol].call(*args)
    end
  end

  def schedule_ping
    EM.add_timer(1) { ping }
  end

  def schedule_health_check
    EM.add_timer(5) do
      check_health
    end
  end

  def ping
    @master.ping do |result|
      @slave.zadd('failover:pongs', Time.now.to_i, @client_id)
      schedule_ping
    end
  end

  def switch_to_master
    @slave.exists 'failover:promoted_at' do |result|
      if result == 0
        @slave.watch 'failover:promoted_at'
        @slave.get 'failover:promoted_at' do |result|
          if !result
            @slave.multi
            @slave.set 'failover:promoted_at', Time.now
            @slave.publish 'failover:promoted', "#{Socket.gethostname}-#{$$}"
            @slave.slaveof 'NO', 'ONE'
            @slave.exec do |result|
              if result
                callback(:on_failover)
              end
            end
          end
        end
      end
    end
  end

  def check_health
    @slave.zremrangebyscore('failover:pongs', '-inf', Time.now.to_i - 5)

    @slave.zcard('failover:pongs') do |result|
      puts "Count #{result}"
      count = result.to_i
      if count == 0
        switch_to_master
      else
        schedule_health_check
      end
    end
  end
end


# EventMachine::run do
#   Failover.new(
#     :master => 'redis://localhost:6379/0',
#     :slave => 'redis://localhost:6380/0',
#     :on_connect => lambda{ |url|
#       puts "Connecting to #{url}"
#     },
#     :on_failover => lambda {
#       puts "Failure detected!"
#     }
#   )
# end