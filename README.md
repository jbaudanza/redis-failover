Overfiew
========

redis-failover provides failover functionality for EventMachine clients
communicating with a master-slave redis configuration.

How it works
============

Each client maintains a connection to both the master and slave redis server.

Each client periodically sends PING commands to the master. If the master fails
to respond to a client, the client use a PUBSUB channel on the slave to ask if
any other clients has seen the master.

If no other clients respond, the client will promote the SLAVE and issue a
PUBLISH message to the other clients.

Limitations
===========

- Only one slave is supported
- Any client can institute a failover.  There is no attempt to reach "quorum"
- No attempt is made to maintain any data consistency after a failover.

Usage
=====

The failover interface uses two callbacks: `connected` and `failover`.

```ruby
failover = Failover.new

# The connected callback will be made when an initial connection is made to
# the master, and then again if a failover happens.
failover.on(:connected) do |redis|
  # Do your thing. redis is an instance of EM::Hiredis::Client
end

# This is called when a client initiates a failover. This callback will
# only happen on the client that initiated the failover. This is a good place
# to handle any system alerts.
failover.on(:connected) do |redis|
  # Send an alert to an administrator
end
```

TODO
====

 - configuration options
 - gemify