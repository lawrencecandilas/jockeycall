# `jockeycall`

`jockeycall` is a Perl application that can be used to deliver a 24/7 radio-station-like experience.  

`jockeycall` functions by selecting a track in properly arranged schedule directories, and either tell `ezstream` to play it, or call a command to play it.  State is tracked in an SQLite database; song length info is cached in a separate SQLite database.

Currently only .mp3 files are supported.

## Requirements And Dependencies

`jockeycall` is written in Perl and was developed on a Debian 11 system.

Code is factored out into modules, which are expected to be in the directory `../lib/jockeycall-modules` relative to the main executable.

`jockeycall` relies on the `mp3info` command to get the duration of MP3 files.  This is included in the `bin` directory.  If this is missing `jockeycall` will not work.

Below is a list of dependencies.  Dependencies not included are likely in your distro's package manager (they're definitely in Debian's).

* 'perl' - development has used v5.32.1.  Any v5 version equal or later than that should work.

* The 'DBI::SQLite' Perl module - so Perl can talk to SQLite databases.  On Debian, `apt-get install libdbd-sqlite3-perl` will take care of this.  It is also easily installable via CPAN.

* `mp3info` (included)

* `ezstream` - if using ezstream integration

* `madplay`/`lame` - recommended to make `ezstream` work well, can also be used for direct local playback

* `aplay` - for direct local playback under ALSA

* `sox` - to apply effects to the audio

## Why `jockeycall` Is Better Than A Playlist

Just about all audio player tools will run through a playlist, and loop through it, and even loop through it continuously and shuffle that list on each pass.  This is great, and is a quick-and-dirty way to setup web-based audio streaming, but it doesn't behave like a real radio station.

- Real radio stations follow a daily/week schedule - i.e. there is the concept of a list of shows and a day/time they should play.

- Real radio stations randomize the songs played during a show.

- Real radio stations will periodically play audio not related to the current show - they will play "links", or other optional interstitial audio every X minutes - things like bumpers, station IDs, and commercials.

If you want something running for days or weeks (haven't tested years yet) unattended, and are willing to put in the work to create schedules, then `jockeycall` is here for you.

## How does `jockeycall` work?

A bit more details on the two methods `jockeycall` works to play a track:

* Integration with ezstream - `jockeycall` will integrate with ezstream's "program" method, and through this can stream to an existing Icecast network streaming setup.

* Custom integration - `jockeycall` may be set to call any command when it wants to play a file - allowing you to play tracks using any method that's callable through the command line.  This method is the one to use if you want to hear the audio out of that system's speaker.

### Preparation - Defining Your Schedule And Shows

Before `jockeycall` can do its magic, it's necessary to arrange the audio files into a directory/folder structure that expresses the shows, schedules, and "periodics", and provide `jockeycall` a writeable place to maintain the play history and data on audio files it finds.  Currently this is done with flat files.

### The Overall Flow Of `jockeycall`

`jockeycall` takes various "subcommands" that further detail what you want `jockeycall` to do.

Something must call `jockeycall` with the subcommand "next" each time a new track is to be played.  The channel directory must be defined in the JOCKEYCALL_CHANNEL environment variable.

`bash$ JOCKEYCALL_CHANNEL=/path/to/channel jockeycall.pl next` 

This is a summary of what happens when that's done:
 
1. The channel configuration is read and parsed.

2. The current system time is obtained, and `jockeycall` finds out what show should be playing.

3. Using state information from the last call -- are we transitioning to a new show?  If so, do housekeeping and clear history.

4. Next, a track (audio file) is selected from the schedule's timeslot track directory, checking against a history maintained for that channel.  That can be chosen randomly, or in series.

5. Then, for `ezstream` integration the path to that audio file is output.  For custom integration, the custom command is executed--the path of the audio file is output where % appears in the command definition.

6. `jockeycall` exits.

Something must call `jockeycall` over and over - and that something can be `jockeycall` itself, if called with the "transmit" subcommand.

`bash$ jockeycall.pl transmit /path/to/channel` (`transmit` subcommand doesn't require JOCKEYCALL_CHANNEL environment variable)

* `ezstream` normally works with a single file or a playlist, but has an option to call a program to fetch a new track.  `jockeycall` was initially designed to work with this feature of `ezstream`.

Therefore `jockeycall` is not really a background process-it's called each time something needs a new track to play and its job is to tell it what track to play and nothing further.  `jockeycall` will get its state from data left over from the last call and update that state before exiting.  If `jockeycall.pl transmit` is used, it will hang around in the foreground, continuously calling `jockeycall.next` or waiting on `ezstream` to finish.  It can be launched in a `screen` or `tumx` session to place it in the background.

* Any amount of time can pass between calls to `jockeycall`.  Days, weeks, whatever.

* Audio files and schedule directories can be added or removed at any time that `jockeycall` isn't actually running.

`jockeycall` can be a little slow, especially with shows with many files that it encounters for the first time.  If streaming to Icecast, it's likely buffered, so it's not often you will hear pauses in the audio.  If you do, IMHO it recreates the experience of real radio stations where sometimes the DJ was asleep at the wheel for a few seconds.

## Requirements

`jockeycall` is written in Perl and was developed on a Debian 11 system.

Code is factored out into modules, which are expected to be in the directory `../lib/jockeycall-modules` relative to the main executable.

`jockeycall` relies on the `mp3info` command to get the duration of MP3 files.  This is included in the `bin` directory.  If this is missing `jockeycall` will not work.

# Built-In `ezstream` integration

`jockeycall` was initially exclusively designed to be called by `ezstream`, and is ready to do that as long as you have `ezstream` locally installed or built.  `jockeycall` must be told where `ezstream` lives on your system in the global jockeycall.conf file.

Other things you'll need:

* `ezstream` is designed to send audio to a working icecast server, so you need that running as a requirement as well.  The XML configuration file you give to `ezstream` will specify the Icecast "mountpoint".

* You really want the stream `ezstream` sends to your icecast server to be a constant bitrate, otherwise listener connections may drop on bitrate changes.  `lame` and `madplay` will need to be installed for this purpose.

* `sox` can be used to apply effects to the audio such as compression and equalization.

Example XML configuration files are provided.

## Under The Hood - `ezstream`'s "`program`" Intake Method

To play well with `ezstream`, `jockeycall` heavily relies on `ezstream`'s "`program`" method of intake.

Some acrobatics with environment variables and symlinks are needed because `ezstream` doesn't allow specifying of arbitrary command line parameters.

