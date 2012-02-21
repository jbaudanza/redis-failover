require 'eventmachine'
require 'em-hiredis'
require 'socket'
require 'logger'

class Failover
  attr_accessor :logger

  @@client_id = 0

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

    @client_id = @@client_id
    @@client_id += 1
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

    @master.callback do
      ping_master
      schedule_health_check
    end

    @slave.callback do
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

            # This key won't exist in the nomimal case
            @slave.del 'failover:promoted_at'

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

    # XXX: It would be nice if em-hiredis allowed you to subscribe to multiple
    # channels at once
    ['failover:promoted',
     'failover:gossip_request',
     'failover:gossip_response'].each do |channel|
      @subscriber.subscribe(channel)
    end

    @subscriber.on(:message) do |channel, param|
      case channel
      when 'failover:promoted'
        logger.warn("MASTER host failed. SLAVE promoted by #{param}")
        @master.close_connection
        @subscriber.close_connection
        callback(:on_connect, @options[:slave])
      when 'failover:gossip_request'
        on_gossip_request(param)
      when 'failover:gossip_response'
        on_gossip_response(param)
      end
    end
  end

  private

  def on_gossip_request(sender_id)
    logger.info("gossip request received from #{sender_id}")
    if seen_master_recently?
      @slave.publish 'failover:gossip_response', client_id
    end
  end

  def on_gossip_response(sender_id)
    @probation = false
  end

  def callback(symbol, *args)
    if @options[symbol]
      @options[symbol].call(*args)
    end
  end

  def schedule_ping
    # XXX: Magic number
    EM.add_timer(1) { ping_master }
  end

  def schedule_health_check
    EM.add_timer(5) do
      check_health
    end
  end

  def ping_master
    puts "ping #{client_id}"
    @master.ping do |result|
      puts "pong"
      @last_pong = Time.now.to_i
      schedule_ping
    end
  end

  def last_pong_age
    if @last_pong
      Time.now.to_i - @last_pong
    end
  end

  def seen_master_recently?
    # XXX Magic Number
    last_pong_age < 10 if @last_pong
  end

  def promote_slave
    @slave.exists 'failover:promoted_at' do |result|
      if result == 0
        @slave.watch 'failover:promoted_at'
        @slave.get 'failover:promoted_at' do |result|
          if !result
            @slave.multi
            @slave.set 'failover:promoted_at', Time.now
            @slave.publish 'failover:promoted', client_id
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

  def client_id
    "#{Socket.gethostname}-#{$$}-#{@client_id}"
  end

  def check_health
    puts "health check #{client_id}"

    if not seen_master_recently?
      if @probation
        promote_slave
        return
      else
        logger.info("putting master on probation")
        @probation = true
        @slave.publish 'failover:gossip_request', client_id
      end
    end

    schedule_health_check
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