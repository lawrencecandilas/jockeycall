# `jockeycall`

`jockeycall` is a Perl application that can be used to deliver a 24/7 radio-station-like experience when hooked into an ezstream/Icecast Internet radio setup.  

## Why `jockeycall` Is Better Than Giving `ezstream` A Flat, Static .M3U 

It's possible to have `ezstream` loop through a static .M3U playlist and send audio to an Icecast server.  `ezstream` can even randomize the playlist each time it loops through it.

This is a quick-and-dirty way to setup web-based audio streaming, but it doesn't behave like a real radio station.

Real radio stations have the following features:

- They follow a schedule - i.e. there is the concept of a list of shows and a day/time they should play.

- They will track play history and not play the songs within a given show in the same order each time.

- They will play "links", or other optional interstitial audio every X minutes - things like bumpers, station IDs, and commercials.

`jockeycall` is hookable into `ezstream` and can provide this experience.

## How does `jockeycall` work?

### Preparation - Defining Your Schedule And Shows

Before `jockeycall` can do its magic, it's necessary to arrange the audio files into a directory/folder structure that expresses the shows, schedules, and "periodics", and provide `jockeycall` a writeable place to maintain the play history and data on audio files it finds.  Currently this is done with flat files.

### `ezstream`'s "`program`" Intake Method

Overall, `jockeycall` heavily relies on `ezstream`'s "`program`" method of intake.

Some acrobatics with environment variables and symlinks are needed due to that option's inflexibility.

### The Overall Flow Of `jockeycall`

Once `jockeycall.pl` gets called by `ezstream`, the following is a simplified flow of what happens:

-- the channel configuration is read and parsed,

-- we get the current system time and find out which show we are "on" according to the schedule,

-- are we transitioning to a new show?  do housekeeping and restart history;

-- a track (audio file) is selected, checking against a history maintained for that channel,

-- and then the path to that audio file is output.

`ezstream` will then stream the file provided by `jockeycall.pl`, and the process repeats.

Therefore `jockeycall` is not a background process-it's called each time `ezstream` needs a new track to play and its job is to tell it what track to play and nothing further.  `jockeycall` will get its state from data left over from the last call and update that state before exiting.  Any amount of time can pass between calls to `jockeycall`.  Audio files and schedule directories can be added or removed at any time that `jockeycall` isn't actually running.

`jockeycall` can be a little slow, especially with shows with many files that it encounters for the first time, but since your Icecast stream is probably buffered, it's not often you will hear pauses in the audio.  If you do, IMHO it recreates the experience of real radio stations where sometimes the DJ was asleep at the wheel for a few seconds.

## Requirements

`jockeycall` is written in Perl and was developed on a Debian 11 system.  Code is factored out into modules, which are expected to be in the directory `../lib/jockeycall-modules` relative to the main executable.

`jockeycall` relies on the `mp3info` command to get the duration of MP3 files.  This is included in the `bin` directory.  If this is missing `jockeycall` will not work.

`jockeycall` is designed to be called by `ezstream` so that's a requirement.  You may also want `madplay` and `sox` if you want to process the audio `ezstream` is sending to icecast, for example to be a specific bitrate or to add audio compression.  Example XML configuration files are provided.

`ezstream` is designed to send audio to a working icecast server, so that is a requirement as well.  The XML configuration file you give to `ezstream` will specify the Icecast "mountpoint".

