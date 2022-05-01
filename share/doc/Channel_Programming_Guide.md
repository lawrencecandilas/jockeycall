`jockeycall` - Channel Programming Guide
========================================
[WIP]

Terminology
===========
Let's begin with some terms as used and understood by `jockeycall` and this guide:

- track: A "track" is simply an .mp3 file.

- timeslot: A "timeslot" is a specific time of day, and represents what you want playing from that time until the next timeslot.

- timeslot portion: Each timeslot can have one or more portions with various settings. 
 
- periodic: A "periodic" is a collection of one or more tracks that should play (if possible) every X minutes - X can be 2, 3, 4, 5, 6, 10, 15, 20, 30, 60, 120, 240, 480, 720.  
 - Periodics can be associated to the entire channel, or a timeslot.
 - Periodics for both channels and the current timeslot will play when defined.
 - If a track runs over an interval by more than a few minutes, `jockeycall` will skip it.

- interval: X above is called an "interval".

Overall, what `jockeycall` plays and when is defined by a directory structure - and that's how most of the above is defined.

`jockeycall` will look into specific places in the directory structure according the current time.  The names of directories and subdirectories will control behavior.  Things can be added, moved, and deleted anytime as long as `jockeycall` isn't actively scanning and working with the directories, which it will do only when called by `ezstream` to fetch a new track.

- A lockfile mechanism exists to make sure two `jockeycall` invocations don't step on each other.  Future development might include a live channel editing utility that works with this mechanism.  For now, if you make changes after a track starts to play that is known to give you enough time, you should be safe to make live changes.

Creating A Channel
==================
The first step in creating a channel is creating and dedicating a directory to it on your filesystem.  

The path to your channel directory is passed to `jockeycall` as a parameter when it is called, it's not stored in a config file.  `jockeycall` doesn't care where it lives on your filesystem as long as everything is readable and the database and log directories are writable.

A file named `config` is expected to be in the channel directory and is where `jockeycall` will look for configuration items specific to your channel.

- This is separate from the global `/etc/jockeycall.conf` or `/opt/jockeycall/etc/jockeycall.conf` file.  The `jockeycall.conf` file contains global options that affect any channel.

Intermission Setup
==================
If `jockeycall` can't find any schedule timeslots (e.g. your schedule subdirectory is empty), or the current schedule timeslot has come to an end, `jockeycall` will go into intermission mode and play intermission tracks.  The intermission tracks are a good fallback to have ready while experimenting or testing and something you should setup right away.

- If `jockeycall` can't find any schedule timeslots and can't find any intermission tracks either, you'll simply hear the "Technical Difficulties" track (defined in the config file) play over and over until a schedule timeslot is found.

The subdirectory that contains intermission tracks is defined in the channel config file.

During intermission, `jockeycall` will select tracks from the intermission directory in random order and play them, maintaining an intermission history separate from anything else going on in the channel.  Once it goes through all of them, it will reset the intermission history and start again.

- A simple way to get `jockeycall` to simply play the same track over and over is to place one track in the intermission directory, and have no timeslot directories in your schedule directory.

Channel `config` file
=====================
In this directory, a file needs to exist named `config`, and it will contain configuration directives for your channel.

Various directives will identify subdirectories relative to the channel directory.

There are also a few attributes such as `day_flip_at` and `random_percent`.  Those are discussed in detail further on below.

The `schedule` subdirectory
===========================
The first level of your schedule directory ...

Example:	/path/to/channel/dir/schedule

... will have one or more subdirectories that represent days of the week.

Example cont.:	/path/to/channel/dir/schedule/weekday
		/path/to/channel/dir/schedule/weekend	

The names of the subdirectories are set by directives in the configuration file.

- You don't need 7 subdirectories for each day of the week, you can use the same subdirectory for each weekday and a separate one for the weekend, for example, or even the same subdirectory across all 7 days if you don't want to do a special weekend schedule.

- The configuration directive `day_flip_at` determines what time `jockeycall` will move to the next day of the week.  This doesn't have to be at midnight.

Timeslot subdirectories
=======================
Within each of those subdirectories will be *timeslots* - which represent a specific time of day.  The format is `1HHMM` where HH is 00 to 23, and MM is 01 to 59.  The leading `1` is required.

- Midnight is `10000`.

Example cont.:	/path/to/channel/dir/schedule/weekday/10400
		/path/to/channel/dir/schedule/weekday/10900
							.
							.
							.

		/path/to/channel/dir/schedule/weekend/10600
		/path/to/channel/dir/schedule/weekend/11200
							.
							.
							.

Your scheme can be as complicated or as simple as you like.  If you have no timeslot subdirectories, or they exist but are empty,`jockeycall` will go into intermission mode.

Timeslot portion subdirectories
===============================
Within a timeslot subdirectory will be one or more *timeslot portion* subdirectories.  

It is in this subdirectory that tracks are expected.
 
The name of this subdirectory communicates how you want `jockeycall` to process the tracks in the timeslot portion.
These directories must follow the below format to be recognized by `jockeycall`.

`t-NNN-PlayOrder-Repetition-History-Limit(optional)`

- The leading `t` is required and the options are separated by `-`'s.

- A timeslot subdirectory must contain at least one portion.  If you dump tracks right in the timeslot subdirectory `jockeycall` will ignore them.

Here's what each of the options in the subdirectory name mean and control:

- NNN: A number - it doesn't matter what it is.  The purpose of this number is to control the order of the timeslot portions.

- PlayOrder: This can be `ordered` or `random`; this option must be specified.  If the option is `ordered`, `jockeycall` will go through the tracks in alphabetical name order.  If the option is `random`, `jockeycall` will go through the tracks in a random order.

-- If you want a different order than alphabetical name order, prepend your track filenames with numbers (including leading zeroes) and specify the order manually.  E.g. 001-firsttrack.mp3, 002-secondtrack.mp3, etc.

- Repetition: This can be `cycle` or `once`; this option must be specified.  If the option is `cycle`, `jockeycall` will play the specified tracks again if it runs out of tracks during the timeslot.  If the option is `once`, `jockeycall` will move on to the next timeslot portion, or intermission if no more portions are left in the current timeslot.

- History: This can be `newhistory` or `samehistory`; this option must be specified.  If the option is `newhistory`, `jockeycall` will reset the history when it enters the timeslot portion.  If the option is `samehistory`, `jockeycall` will keep it around and only reset it when it goes through all the tracks.

- Limit: This is a number; this option is optional.  If specified, `jockeycall` will move on to the next timeslot portion after playing this many tracks.

So... given the below example:

Example cont.:	/path/to/channel/dir/schedule/weekday/10400/t-010-ordered-once-newhistory/intro.mp3
		/path/to/channel/dir/schedule/weekday/10400/t-020-random-cycle-newhistory/song1.mp3
		/path/to/channel/dir/schedule/weekday/10400/t-020-random-cycle-newhistory/song2.mp3
		/path/to/channel/dir/schedule/weekday/10400/t-020-random-cycle-newhistory/song3.mp3
												.
												.
												.

		* The first subdirectory might contain just one track - an introduction.

		* Then, the second subdirectory could contain many tracks which would be the content we want to present at 0400 hours.

The 'periodic' subdirectories
=============================
As mentioned above, periodics are collections of tracks that play every X minutes.  

There are two levels of periodics - channel-level, and timeslot-level.

The location and directory name of the channel-level periodics is defined in the channel config file.  Timeslot-level periodics are always named 'periodic' and will appear in the timeslot.

Periodic interval subdirectories
================================
Inside the periodic subdirectory (channel-level or timeslot level) may appear a number representing an *interval*, or how often you want the interval portions within to be looked at.

Example:	

		* Inspected for interval portions near 20-minute mark, 3x an hour

		/path/to/channel/dir/periodic/20	

		* Inspected for interval portions near 60-minute mark, on the hour

		/path/to/channel/dir/periodic/60

		* Inspected for interval portions near 120-minute mark, once every 2 hours.

		/path/to/channel/dir/periodic/12

- Valid intervals are: 2, 3, 4, 5, 6, 10, 15, 20, 30, 60, 120, 240, 480, 720.

- Intervals represent the 24-hour day divided by X - so, for example, there are exactly 12 intervals for the value 120 and they occur at midnight, 2am, 4am, 6am, 8am, etc.  Intervals are not relative to anything else but midnight.

- If `jockeycall` is called too late after an interval, it will skip it.  There is no absolute guarantee that `jockeycall` will play anything in a periodic subdirectory.

 - If this was not done: could you imagine if you had `jockeycall` running for a few days, stopped it for a week, then restarted?  You would hear nothing but periodic tracks for a long time, and then what about those missed intervals?  

 - `Mandates` are what should be used if there is a need for tracks to absolutely be played at certain times.

Periodic interval portion subdirectories
========================================
Within the numeric-named subdirectory representing the interval will be one or more interval-portion subdirectories.  This is similar in concept to timeslot-portion subdirectories.  Each interval portion subdirectory needs one, tracks placed outside of one will be ignored.

`p-NNN-PlayOrder-Limit`

- The leading `p` is required and the options are separated by `-`'s.

Here's what each of the options in the subdirectory name mean and control:

- NNN: A number - it doesn't matter what it is.  The purpose of this number is to control the order of the interval portions.

- PlayOrder: This can be `ordered` or `random`; this option must be specified.  If the option is `ordered`, `jockeycall` will go through the tracks in alphabetical name order.  If the option is `random`, `jockeycall` will go through the tracks in a random order.

 - If you want a different order than alphabetical name order, prepend your track filenames with numbers (including leading zeroes) and specify the order manually.  E.g. 001-firsttrack.mp3, 002-secondtrack.mp3, etc.

- Limit: This is a number or the word `all`; this option must be specified.  This is how many tracks in the interval portion you want to play.  `jockeycall` doesn't keep a history of interval portion tracks, so it's possible you may hear the same track often, unless you use round robins.

Concrete examples:

Example:	* Every 20 minutes ...
	
		/path/to/channel/dir/periodic/20/p-001-ordered-3
		
		* ... `jockeycall` will first play the three tracks in this subdirectory, in order.
		
		/path/to/channel/dir/periodic/20/p-002-random-3

		* ... `jockeycall` will then play 3 random tracks from this subdirectory.
		* ,.. then continue on with the schedule.

		* Every hour, `jockeycall` will always play the first track found here.

		/path/to/channel/dir/periodic/60/p-001-ordered-1

Periodic round robin subdirectories
===================================
`jockeycall` doesn't keep a history of periodic tracks played, but the channel designer can avoid over-reptitive delivery of periodic tracks by defining a round robin.

This is done by ensuring a subdirectory entitled `rr` appears within a channel-periodic or timeslot-periodic subdirectory.  

The next inner subdirectory will be *another* level of subdirectories, each in the following format:

`Interval-RoundRobinSlot-RoundRobinEnd`

- Interval: This is a number; and is required - and it must be one of the valid interval values described above.

- RoundRobinSlot: This is also a number; and is also required.

- RoundRobinEnd: This can either be omitted, or 'end'.  

The way round robin works is very simple, each time an interval is recognized and processed, a "round robin slot number" for that interval will be incremented (saved and persisted across calls); if the round robin directory has `end` in its name, it's reset to 1 after processing. 

- If no round robin directory has `end` in its name, `jockeycall` will reset it to 1 after it reaches 16.  16 is also the maximum number of round-robin slots.

`jockeycall` will then look in the subdirectory that matches the interval and the current round robin slot number.  If nothing is there, `jockeycall` skips over the subdirectory.

Example:

		/path/to/channel/dir/periodic/rr/20-1 ....
		/path/to/channel/dir/periodic/rr/20-2 ....
		/path/to/channel/dir/periodic/rr/20-3-end ....

So if you only have tracks in 20-2 and 20-3-end, you'll only hear tracks when in the *second* and *third* 20 minute mark after the top of the hour.  This is how you can change behavior depending on "which" interval during the hour or day.

If you need something more complicated, use schedule timeslots instead of periodics.

The `intermission` subdirectory
===============================
Tracks in the intermission subdirectory will play when there is no active schedule timeslot.

Channel-level periodics will play during intermission.  You can place a 'periodic' subdirectory and it will be processed the same way as timeslot-level periodics above.

If your intermission subdirectory is empty and `jockeycall` determines it must play from it, `jockeycall` will deliver the "Technical Difficulties" track as defined in the channel's `config` file.  Defining this is not optional.


