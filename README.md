Overfiew
========

redis-failover provides failover functionality for a system of EventMachine
clients communicating with a master-slave redis configuration.

How it works
============

Each EventMachine client maintains a connection to both the master and slave
redis servers.

Each client will periodically send PING comamnds to the master. The slave
connection will be used to by clients to gossip about the health of the master.

If the master fails to respond to a client's PING, the client will issue
a PUBSUB message to ask if any other clients have seen the master.  If no
response is received, the client will promote the SLAVE and issue a PUBLISH
message to the other clients of the promotion.

Limitations
===========

- Only one slave is supported
- Any client can institute a failover.  There is no attempt to reach "quorum"
- No attempt is made to maintain any data consistency after a failover.

Usage
=====

The failover interface uses two callbacks: `connected` and `failover`.

```ruby
failover = Failover.new(
	# URL of master, required,
	:master => 'redis://master.example.com:6379/0',

	# URL of slave, required.
	:slave => 'redis://master.example.com:6379/0',

	# The number of seconds a master can go missing without being put on
	# probation. Defaults to 10
	:grace_timeout => 10,

	# The number of seconds a master can be on probation before a failover
	# is issued. Defaults to 10.
	:period_timeout => 10
	)

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
