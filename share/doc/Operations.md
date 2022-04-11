Operations
==========

jockeycall's purpose is to look at a schedule structure and deliver the path
of a track to standard output.  This integrates with ezstream, and allows a
radio-station like experience through an existing ezstream-icecast flow.

In the internal logic of jockeycall, one of the last subroutines called is
"DeliverTrack".

If the track is an actual MP3 file (determined by file name, ending in .mp3),
the DeliverTrack function will output the path; ezstream then picks it up and
streams it to icecast, and any connected listeners hear the track.

The other possibility is an operation file (ending in .opr).  An operation
file is a small text file that is intended to provide additional instructions
to jockeycall.

The first line in an operation file is essentially a command.  Subsequent lines
in the file are typically paths to .mp3s, but they don't have to be.

An operation file will most likely take multiple jockeycall rounds to
complete.

* Operation files are ignored if a timeslot is in the yellow or red zone.
* Operation files are ignored if a channel is in intermission.
* Operations are cancelled once a timeslot enters/passes the yellow or red
  zone, or if a channel enters intermission.

Operation File Format
--------------------

An operation file (.opr) consists of the following:

- First non-blank non-comment line:
  Command and parameters
- Subsequent non-blank non-comment lines:
  Track list, relative to the current folder

The following applies to the entire file:

* Blank lines ignored.
* Lines beginning with # are considered comments and ignored.

Some directives will make sense as part of a schedule's main program, and some
will make sense as part of periodics.

Available Directives
````````````````````

playall [consider-history]

The playall directive will play each track in the list of tracks that follows,
in order.

* If the parameter "consider-history" is present, tracks will be skipped if
  they appear in the timeslot's history.

Example:

=== Beginning of example file
playall
/album01/song01.mp3
/album01/song02.mp3
=== End of example file

