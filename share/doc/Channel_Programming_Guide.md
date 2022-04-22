`jockeycall` - Channel Programming Guide
========================================

[WIP]

Let's begin with some terms as used and understood by `jockeycall` and this guide:

- track: A "track" is simply an .mp3 file.

- timeslot: A "timeslot" is a specific time of day, and represents what you want playing from that time until the next timeslot.

- periodic: A "periodic" is a collection of one or more tracks that should play (if possible) every X minutes - X can be 2, 3, 4, 5, 6, 10, 15, 20, 30, 60, 120, 240, 480, 720.  
 - Periodics can be associated to the entire channel, or a timeslot.
 - Periodics for both channels and the current timeslot will play when defined.
 - If a track runs over an interval by more than a few minutes, `jockeycall` will skip it.

- interval: X above is called an "interval".

- mandate: A "mandate" is a collection of one or more tracks that must play at specific times, regardless of what else is happening.
 - Mandates can only be associated to an entire channel.
 - Mandates will always play.

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

- A simple way to get `jockeycall` to simply play the same track over and over is to place one track in the intermission directory, and have no timeslot directories.

Channel `config` file
=====================
In this directory, a file needs to be exist named `config`, and it will contain configuration directives for your channel.  Various directives will identify subdirectories relative to the channel directory.

The `schedule` subdirectory
===========================

The first level of your schedule directory will have one or more subdirectories that represent days of the week.  The names of the subdirectories are set by directives in the configuration file.  You don't need 7 subdirectories for each day of the week, you can use the same subdirectory for each weekday and a separate one for the weekend, for example, or even the same subdirectory across all 7 days if you don't want to do a special weekend schedule.

- The configuration directive `day_flip_at` determines what time `jockeycall` will move to the next day of the week.  This doesn't have to be at midnight.

Within each of those subdirections will be *timeslots" - which represent a specific time of day.  The format is `1HHMM` where HH is 00 to 23, and MM is 01 to 59.  The leading `1` is required.

- Midnight is `10000`.

Timeslot subdirectories
=======================

The 'periodic' subdirectories
=============================

The `intermission` subdirectory
===============================

