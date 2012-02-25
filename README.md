== Client slave promotion algorithm ==
When a client tries to write:

- Perform Write

- If write fails
  - Ask the slave if the master is down
  - If slave says the master is down
     - Promote slave to master
     - Continue Write
  - If the slave is down, Fatal error

Questions
- Perhaps other clients should poll the slave to see if it has been promoted
- How does the redis client handle writes.  Will it buffer them until a connection is made?
- Perhaps clients should continually poll to detect a failure before something in the app does
- Can we detect EC2 rolling reboots and do a pre-emptive slave promotion?
- Client can use the slave channels to gossip with other clients
- When a master crashes, and then comes back online, it should be smart enough to become a slave of the new master
- Is it possible to have redis guarantee that slaves are updated before accepting a write?
- em-hiredis doesn't propagate connection failures to the client..



== TODO:
 - Add some kind of "confirmation" step from another peer, perhaps from another availability zone
 - Handle the case when the slave is down
 - Perhaps a "grace period" after startup
 - Merge timers into 1
 - gemify
 - perhaps these log warnings should be errors


Look at this for tips:
https://github.com/zealot2007/redis-cluster-monitor