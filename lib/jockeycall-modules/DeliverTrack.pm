package DeliverTrack;
require 'Debug.pm';
require 'Concurrency.pm';
require 'Playlog.pm';
require 'DataMoving.pm';
require 'Operation.pm';
use File::Basename;
use parent 'Exporter';

# Functions for the actual track delivery
# Track delivery is outputting an mp3 filename to stdout for ezstream

our @EXPORT=qw(
	check_track
	now_play
	technical_difficulties
	);

# Base directory for log files
# This is set by the first call to debug_message_management()
our $play_log_basedir='.';

# Debug log file, within $debug_log_basedir
our $play_log_file='playlog.txt';

sub check_track
{
	Debug::trace_out("*** DeliverTrack::check_track($_[0])");

# Parameters/info
#
# Verify track is playable.
#
# By playable, we mean that it exists and is a file.
# Additional checks may be prudent.
#
# $_[0]: Track to verify.
# Returns 1 if issue with track, 0 if OK.

	if(! -e $_[0])
	{
		Debug::error_out("[DeliverTrack::check_track] Track \"$_[0]\" not found.");
		return 0;
	}
	if(! -f $_[0])
	{
		Debug::error_out("[DeliverTrack::check_track] Track \"$_[0]\" is not a file.");
		return 0;
	}

	return 1;
}


sub now_play_from_operation
{
	Debug::trace_out("*** DeliverTrack::now_play_from_operation(\"".$_[0]."\",$_[1],$_[2])");
#
# Parameters/info
#
# $_[0]: Output this track for playing, then end.
#        If the track is an operation, it will kick off the operation and
#        hand off to that process.  Subsequent operation steps will happen a
#        lot earlier on jockeycall's next invocation.
# $_[1]: Text to place in "now-playing" field.  If null, uses $_[0].
#
# Intended to be called from Operation module.
# Metadata updating is not this routine's responsibility.
# Neither is validation of track.

        if($_[1] eq '')
        {
                DataMoving::set_rkey('now-playing',basename($_[0]));
        }
        else
        {
                DataMoving::set_rkey('now-playing',$_[1]);
        }

	if($ENV{'JOCKEYCALL_SIMULATION_MODE'}==1)
	{
		my %t=DataMoving::get_metadata(main::md5_hex($_[0]));
		print "$_[0];$t{'l'}\n";
	}else{
                Playlog::private_playlog_out($_[0]);
                if($_[2]==0)
                {
                        if($_[1] eq '')
                        {
	                	Playlog::public_playlog_out(basename($_[0]));
                	}else{
        	        	Playlog::public_playlog_out($_[1]);
                        }
                }
        	print "$_[0]\n";
	}

	# This will only do anything if someone called
	# BannerUpdate::set_doUpdate_flag()
        BannerUpdate::set_timeslot_info($main::current_timeslot,$main::next_timeslot);
        BannerUpdate::schedule_flip();

        Concurrency::succeed();
}


sub now_play
{
	Debug::trace_out("*** DeliverTrack::now_play(\"".$_[0]."\",$_[1],$_[2])");
#
# Parameters/info
#
# $_[0]: Output this track for playing, then end.
#        If the track is an operation, it will kick off the operation and
#        hand off to that process.  Subsequent operation steps will happen a
#        lot earlier on jockeycall's next invocation.
# $_[1]: Text to place in "now-playing" field.  If null, uses $_[0].
# $_[2]: 1 if this should not be noted in public playlog. 
# Example is if playing OOB tracks.
#
# Metadata updating is not this routine's responsibility.
# Neither is validation of track.
# Use check_track() beforehand if not sure.

	if( (lc(substr($_[0],4))!='.opr') )
	{
		Operation::kickoff($_[0]);
		# If this returns something went wrong with the kick off and
		# we'll report the technical difficulty.
		technical_difficulties();
	}

	if($_[1] eq '')
	{
		DataMoving::set_rkey('now-playing',basename($_[0]));
	}
	else
	{
		DataMoving::set_rkey('now-playing',$_[1]);
	}

        if($ENV{'JOCKEYCALL_SIMULATION_MODE'}==1)
        {
                my %t=DataMoving::get_metadata(main::md5_hex($_[0]));
                print "$_[0];$t{'l'}\n";
        }else{
	        Playlog::private_playlog_out($_[0]);
	        if($_[2]==0)
        	{
	                if($_[1] eq '')
                	{
                       		Playlog::public_playlog_out(basename($_[0]));
	               	}else{ 
        	       	        Playlog::public_playlog_out($_[1]);
        		}
	        }
                print "$_[0]\n";
        }

	# This will only do anything if someone called
	# BannerUpdate::set_doUpdate_flag()
	BannerUpdate::set_timeslot_info($main::current_timeslot,$main::next_timeslot);
	BannerUpdate::schedule_flip();

	Concurrency::succeed();
} 


sub technical_difficulties
{
	Debug::trace_out("*** DeliverTrack::technical_difficulties()");
	if($Conf::conf{'track_td'} eq '')
	{
		Concurrency::fail('[DeliverTrack::technical_difficulties] CONF_track_td not defined',1);
	}

# Parameters/info
#
# Play technical difficulties track, then end via now_play().
#
# External variables used:
#  $Conf::conf{'basedir'}, $Conf::conf{'track_td'}

	if(!check_track("$Conf::conf{'basedir'}/$Conf::conf{'track_td'}"))
	{
		Concurrency::fail("[DeliverTrack::technical_difficulties] check_track() on CONF_track_td \"$Conf::conf{'track_td'}\" failed",1);
	}	

	now_play("$Conf::conf{'basedir'}/$Conf::conf{'track_td'}","TECHNICAL DIFFICULTIES - PLEASE STAND BY",1);

	Concurrency::succeed(); # ironic
} 


1;

