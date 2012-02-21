require './spec/spec_helper'
require './failover'

MASTER_URL = 'redis://localhost:9010/0'
SLAVE_URL = 'redis://localhost:9011/0'

describe Failover do
  describe "when the master and the slave are alive" do
    before(:all) do
      start_master
      start_slave
    end

    it "should connect successfully" do
      run_with_em do
        Failover.new(
          :master => MASTER_URL,
          :slave => SLAVE_URL,
          :on_connect => lambda{ |url|
            url.should == MASTER_URL
            EM.stop_event_loop
          },
          :on_failover => lambda {
            puts "Failure detected!"
          }
        )
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
      on_connect_count = 0
      test = false

      options = {
        :master => MASTER_URL,
        :slave => SLAVE_URL,
        :on_failover => lambda {
        },
        :on_connect => lambda { |url|
          if test
            url.should == SLAVE_URL
            on_connect_count += 1
            EM.add_timer(1) {
              EM.stop_event_loop
            }
          end
        }
      }

      run_with_em do
        client1 = Failover.new(options)
        client2 = Failover.new(options)

        EM.add_timer(1) do
          on_connect_count = 0
          test = true
          kill_redis('master')
        end
      end

      on_connect_count.should == 2
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
      pending
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
        :slave => SLAVE_URL,
        :on_failover => lambda {},
        :on_connect => lambda { |url|
          url.should == MASTER_URL
        }
      }

      run_with_em do
        client = Failover.new(options)
      end

      pending
    end
    after(:all) do
      kill_redis("master")
    end
  end

  describe "when the client is started with a failed slave and master" do
    it "should raise an error" do
      pending
    end
  end
end