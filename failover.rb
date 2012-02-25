require 'eventmachine'
require 'em-hiredis'
require 'socket'
require 'logger'

class Failover
  include EventMachine::Hiredis::EventEmitter

  attr_accessor :logger

  @@client_id = 0

  def initialize(options={})
    @options = options
    raise ArgumentError("master option required") unless @options[:master]
    raise ArgumentError("slave option required") unless @options[:slave]

    if !@options[:logger]
      @options[:logger] = Logger.new(STDERR)
    end

    connect

    @client_id = @@client_id += 1
  end

  def logger
    @options[:logger]
  end

  def connect
    @master = EM::Hiredis.connect(@options[:master])
    @slave = EM::Hiredis.connect(@options[:slave])
    @subscriber = EM::Hiredis.connect(@options[:slave])

    @current_connection = @master

    @failed = false

    # XXX: Magic number, and too often
    # XXX: Make this a weak reference?
    @timer = EM.add_periodic_timer(1) do
      on_timer
    end

    @master.callback do
      ping_master
      emit(:connected, @master)
    end

    @slave.callback do
      @slave.info do |result|
        if result[:role] == 'master'
          logger.warn("Slave has previously been promoted to master.")
          @master.close_connection
          @subscriber.close_connection
          enter_failed_state
          @current_connection = @slave
          emit(:connected, @current_connection)
        else
          if @master.host == result[:master_host] &&
             @master.port == result[:master_port].to_i

            # This key won't exist in the nomimal case
            @slave.del 'failover:promoted_at'
          else
            @slave.close_connection
            @subscriber.close_connection
            @current_connection = @master
            enter_failed_state
            logger.warn(
                "Expected slave to be connected to #{@options[:master]}, but " +
                "instead is #{result[:master_host]}:#{result[:master_port]}")
          end
        end
      end
    end

    # It would be nice if em-hiredis allowed you to subscribe to multiple
    # channels at once
    ['failover:promoted',
     'failover:gossip_request',
     'failover:gossip_response'].each do |channel|
      @subscriber.subscribe(channel)
    end

    @subscriber.on(:message) do |channel, sender_id, arg|
      case channel
      when 'failover:promoted'
        on_slave_promoted(sender_id)
      when 'failover:gossip_request'
        on_gossip_request(sender_id)
      when 'failover:gossip_response'
        on_gossip_response(sender_id, arg)
      end
    end
  end

  def connection
    @current_connection
  end

  private

  def on_slave_promoted(sender_id)
    logger.warn("MASTER host failed. SLAVE promoted by #{sender_id}")
    @master.close_connection
    @subscriber.close_connection
    enter_failed_state

    @current_connection = @slave
    emit(:connected, @current_connection)
  end

  def on_gossip_request(sender_id)
    return if sender_id == client_id

    logger.info("gossip request received from #{sender_id}")
    if seen_master_recently?
      @slave.publish 'failover:gossip_response', client_id, last_pong_age
    end
  end

  def on_gossip_response(sender_id, pong_age)
    return if sender_id == client_id

    logger.info("gossip response receieved from #{sender_id}")
    take_master_off_probation

    if pong_age < last_pong
      @last_pong = Time.now.to_i - pong_age
    end
  end

  def ping_master
    d = @master.ping 

    d.errback do |error|
      logger.error("redis ping failed: #{error}")
      put_master_on_probation
    end

    d.callback do |result|
      take_master_off_probation
      @last_pong = Time.now.to_i
    end
  end

  def on_timer
    return if @failed

    ping_master

    if is_on_probation?
      if seconds_on_probation > 10
        promote_slave
      end
    elsif not seen_master_recently?
      put_master_on_probation
    end
  end

  def last_pong_age
    Time.now.to_i - @last_pong if @last_pong
  end

  def seen_master_recently?
    # XXX Magic Number
    last_pong_age < 10 if @last_pong
  end

  def seconds_on_probation
    Time.now.to_i - @probation_at if is_on_probation?
  end

  def is_on_probation?
    !!@probation_at
  end

  def promote_slave
    @slave.exists 'failover:promoted_at' do |result|
      if result == 0
        @slave.watch 'failover:promoted_at'
        @slave.get 'failover:promoted_at' do |result|
          if !result
            @slave.multi
            @slave.set 'failover:promoted_at', Time.now.to_i
            @slave.publish 'failover:promoted', client_id
            @slave.slaveof 'NO', 'ONE'
            @slave.exec do |result|
              emit(:failover) if result
            end
          end
        end
      end
    end
  end

  def client_id
    "#{Socket.gethostname}-#{$$}-#{@client_id}"
  end

  def enter_failed_state
    @failed = true
    EM.cancel_timer(@timer)
  end

  def put_master_on_probation
    return if is_on_probation?
    @probation_at = Time.now.to_i
    @last_pong = nil
    @slave.publish('failover:gossip_request', client_id)
    logger.warn("putting master on probation")
  end

  def take_master_off_probation
    if is_on_probation?
      @probation_at = nil
      logger.info('Taking master off of probation')
    end
  end
end
