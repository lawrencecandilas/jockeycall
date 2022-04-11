# jockeycall

jockeycall is a Perl application that can be used to deliver a 24/7 radio-station-like experience when hooked into an ezstream/Icecast Internet radio setup.  

## Why jockeycall can be better than ezstream and a flat, static .m3u playlist

It's possible to have ezstream loop through a static .m3u playlist and send audio to an Icecast server.  ezstream can even randomize the playlist each time it loops through it.

This is a quick-and-dirty way to setup an Internet radio station, but doesn't behave like a real radio station.

Real radio stations have the following features:

- They follow a schedule - i.e. there is the concept of a list of shows and a day/time they should play.

- They will track play history and not play the songs within a given show in the same order each time.

- They will play "links", or other optional interstitial audio every X minutes - things like bumpers, station IDs, and commercials.

jockeycall is hookable into ezstream and can provide this experience.

## How does jockeycall work?

Before jockeycall can do its magic, it's necessary to arrange the audio files into a directory/folder structure that expresses the shows, schedules, and "periodics" or audio files that are played out of the band of the current show's schedule, and provide jockeycall a writeable place to maintain the play history and data on audio files it finds.

Once that's done, here's how things work:

- ezstream can get the next song its supposed to play from a file, from STDIN, or from a program.  

- jockeycall leverages the ezstream configuration's "program" method.  

- The ezstream's configuration XML file should specify jockeycall as the program to call in order to get its next song.

- Unfortunately, we can't directly do this because of a few reasons (explained below) so a wrapper script must be called that then calls jockeycall.  

- Once called, jockeycall will read its configuration, get the current system time, check the schedule and play history for the current show.  It will select a audio file ("track") and output its path.

- ezstream will then stream that file, and call jockeycall again when it's done, and the process repeats

Therefore jockeycall is not a background process-it's called each time ezstream needs a new track to play and its job is to tell it what track to play and nothing further.  jockeycall will get its state from files left over from the last call and update that state before exiting.  Audio files can be added or removed at any time.  

jockeycall can be a little slow, especially with shows with many files that it encounters for the first time, but since your Icecast stream is probably buffered, it's not often you will hear pauses in the audio.  If you do, IMHO it recreates the experience of real radio stations where sometimes the DJ was asleep at the wheel for a few seconds.

## Requirements

jockeycall is written in Perl and was developed on a Debian 11 system.  Code is factored out into modules, which are expected to be in the directory "../lib/jockeycall-modules" relative to the main executable.

jockeycall relies on the mp3info command to get the duration of mp3 files.  This is included in the modules directory.  If this is missing jockeycall will not work.

jockeycall is designed to be called by ezstream so that's a requirement.  You may also want madplay and sox if you want to process the audio ezstream is sending to icecast, for example to be a specific bitrate or to add audio compression.  Example XML configuration files are provided.

ezstream is designed to send audio to a working icecast server, so that is a requirement as well.  The XML configuration file you give to ezstream will specify the Icecast "mountpoint".

