Environment Variables
=====================
A few environment variables can be set to control `jockeycall`.  They are detailed below.

# `JOCKEYCALL_CHANNEL`
This defines the path containing all the data for the channel `jockeycall` is selecting a track for.
This must be set for any call to `jockeycall` unless the `jockeycall transmit` or `jockeycall test` command is used.
The channel path is passed this way for compatibility with `ezstream`'s playlist/metadata program API.

# `JOCKEYCALL_STDOUT_EVERYTHING`
Set to 1 to enable.
This will turn on debug and trace messages, and dump them to `stdout`.
This generates a lot of output and is very useful for debugging and troubleshooting.

# `JOCKEYCALL_CONF`
This tells `jockeycall` where to look for the global configuration file `jockeycall.etc`.
This is not a path, but a keyword.  Valid keywords are:
- `devel`
  `jockeycall` looks in ../etc/jockeycall.conf
- `opt`
  `jockeycall` looks in /opt/jockeycall/etc/jockeycall.conf
If no value is specified, `jockeycall` looks in /etc/jockeycall.conf.

# `JOCKEYCALL_SIMULATION_MODE`
Set to 1 to enable.
This will do two things:
- `jockeycall` won't use the system clock for the current time, but will instead use the value at `JOCKEYCALL_TIMESLOT`.
- make `jockeycall` output the duration of the selected track in seconds, in addition to the path of the selected track.
This provides a mechanism to simluate the behavior of an entire day.

# `JOCKEYCALL_TIMESLOT`
See above.  Only used if `JOCKEYCALL_SIMULATION_MODE` is 1.


