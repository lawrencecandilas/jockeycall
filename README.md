# `jockeycall`

`jockeycall` is a Perl application that can be used to deliver a 24/7 radio-station-like experience when hooked into an ezstream/Icecast Internet radio setup.  
## Why `jockeycall` Is Better Than Giving `ezstream` A Flat, Static .M3U 

It's possible to have `ezstream` loop through a static .M3U playlist and send audio to an Icecast server.  `ezstream` can even randomize the playlist each time it loops through it.  This is great, and is a quick-and-dirty way to setup web-based audio streaming, but it doesn't behave like a real radio station.

- Real radio stations follow a daily/week schedule - i.e. there is the concept of a list of shows and a day/time they should play.

- Real radio stations randomize the songs played during a show.

- Real radio stations will periodically play audio not related to the current show - they will play "links", or other optional interstitial audio every X minutes - things like bumpers, station IDs, and commercials.

`jockeycall` is hookable into `ezstream` and can provide this experience.

## How does `jockeycall` work?

### Preparation - Defining Your Schedule And Shows

Before `jockeycall` can do its magic, it's necessary to arrange the audio files into a directory/folder structure that expresses the shows, schedules, and "periodics", and provide `jockeycall` a writeable place to maintain the play history and data on audio files it finds.  Currently this is done with flat files.

### `ezstream`'s "`program`" Intake Method

Overall, `jockeycall` heavily relies on `ezstream`'s "`program`" method of intake.

Some acrobatics with environment variables and symlinks are needed because `ezstream` doesn't allow specifying of arbitrary command line parameters. 

### The Overall Flow Of `jockeycall`

Once `jockeycall.pl` gets called by `ezstream`, the following is a simplified flow of what happens:

1. The channel configuration is read and parsed.

2. The current system time is obtained, and `jockeycall` finds out what show it's currently playing according to the schedule.

3. Are we transitioning to a new show?  If so, do housekeeping and clear history.

4. Next, a track (audio file) is selected from the schedule's timeslot track directory, checking against a history maintained for that channel,

5. Then, the path to that audio file is output.

`ezstream` will then stream the file provided by `jockeycall.pl`, and when `ezstream` needs something new to play, it will invoke `jockeycall` again and restart the process.

Therefore `jockeycall` is not really a background process-it's called each time `ezstream` needs a new track to play and its job is to tell it what track to play and nothing further.  `jockeycall` will get its state from data left over from the last call and update that state before exiting.  Any amount of time can pass between calls to `jockeycall`.  Audio files and schedule directories can be added or removed at any time that `jockeycall` isn't actually running.

While you can launch `ezstream` directory, `jockeycall` will do this for you easily and simply if you issue a `jockeycall.pl transmit /path/to/channel` - and in this case `jockeycall` will launch `ezstream` with the correct parameters, and loop back and restart `ezstream` if it dies.  In this case you will have a `jockeycall.pl` process hanging around and a second one actually servicing `ezstream`.

`jockeycall` can be a little slow, especially with shows with many files that it encounters for the first time, but since your Icecast stream is probably buffered, it's not often you will hear pauses in the audio.  If you do, IMHO it recreates the experience of real radio stations where sometimes the DJ was asleep at the wheel for a few seconds.

## Requirements

`jockeycall` is written in Perl and was developed on a Debian 11 system.  Code is factored out into modules, which are expected to be in the directory `../lib/jockeycall-modules` relative to the main executable.

`jockeycall` relies on the `mp3info` command to get the duration of MP3 files.  This is included in the `bin` directory.  If this is missing `jockeycall` will not work.

`jockeycall` is currently designed to be called by `ezstream` so that's a requirement.  You may also want `madplay` and `sox` if you want to process the audio `ezstream` is sending to icecast, for example to be a specific bitrate or to add audio compression.  Example XML configuration files are provided.  `ezstream` is designed to send audio to a working icecast server, so that is a requirement as well.  The XML configuration file you give to `ezstream` will specify the Icecast "mountpoint".

