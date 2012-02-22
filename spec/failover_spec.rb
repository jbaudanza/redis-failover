require './spec/spec_helper'
require './failover'

MASTER_URL = 'redis://localhost:9010/0'
SLAVE_URL = 'redis://localhost:9011/0'

describe Failover do
  around(:each) do |example|
    run_with_em(&example)
  end

  before(:each) do
    @options = {
      :master => MASTER_URL, :slave => SLAVE_URL
    }
  end

  describe "when the master and the slave are alive" do
    before(:all) do
      start_master
      start_slave
    end

    it "should connect successfully" do
      failover = Failover.new(@options)

      failover.on(:connected) do |redis|
        redis.port.should == REDIS_MASTER_PORT
        EM.stop_event_loop
      end
    end

    after(:all) do
      kill_redis("master")
      kill_redis("slave")
    end
  end

  describe "when the master fails" do
    before(:all) do
      start_master
      start_slave
    end

    it "should fail over to the slave" do
      client1 = Failover.new(@options)
      client2 = Failover.new(@options)

      on_connected_count = 0
      on_failover_count = 0

      on_connected = lambda do |redis|
        redis.port.should == REDIS_SLAVE_PORT
        on_connected_count += 1

        if on_connected_count == 2
          on_failover_count.should == 1
          EM.stop_event_loop
        end
      end

      on_failover = lambda do
        on_failover_count += 1
      end

      EM.add_timer(1) do
        client1.on(:connected, &on_connected)
        client2.on(:connected, &on_connected)
        client1.on(:failover, &on_failover)
        client2.on(:failover, &on_failover)

        kill_redis('master')
      end

    end

    after(:all) do
      kill_redis('slave')
    end
  end

  describe "when the client is started with a failed master" do
    before(:all) do
      start_slave
    end
    it "should fail over to the slave" do
      failover = Failover.new(@options)

      failover.on(:connected) do |redis|
        redis.port.should == REDIS_SLAVE_PORT
        EM.stop_event_loop
      end
    end
    after(:all) do
      kill_redis("slave")
    end
  end

  describe "when the client is started with a failed slave" do
    before(:all) do
      start_master
    end
    it "should connect to the master" do
      options = {
        :master => MASTER_URL,
        :slave => SLAVE_URL
      }

      failover = Failover.new(options)
      failover.on(:connected) do |redis|
        redis.port.should == REDIS_MASTER_PORT
        EM.stop_event_loop
      end
    end
    after(:all) do
      kill_redis("master")
    end
  end
end