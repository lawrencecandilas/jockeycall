#!/usr/bin/perl

# This is Jockeycall

use POSIX qw(strftime);
use Digest::MD5 qw(md5 md5_hex md5_base64);
use File::Basename;
use File::Copy;
use List::Util qw/shuffle/;

use lib '../lib/jockeycall-modules';
use Utility;
use Debug;
use Conf;
use Concurrency;
use DataMoving;
use DeliverTrack;
use MetadataProcess;

# $ARGV[0] is the subcommand - what we want to do.
#
# - Due to ezstream wackiness, the script name (${'0'}) is also kinda-sorta
#   allowed to set the subcommand, that logic may override it.  See below.
#
# We don't test if command is null or invalid right here because we want to
# allow simple validation of channel config.
#
my $command=$ARGV[0]; $command=~s/^\s+|\s+$//g;

# The subcommands may take parameters.  Where the parameters are depends
# on some logic below ...
my $parameter;

# It all begins with a channel.  All things that make up a channel are in a
# given directory. 
#
# $ENV{'JOCKEYCALL_CHANNEL'} is that directory, unless the subcommand is
# "transmit" - then it's $ARGV[1]
# 
# Why is an environment variable used?  ezstream wackiness. 
#
if($ARGV[0] eq 'transmit')
{
	if($ARGV[1] eq ""){Utility::usage; exit 0;}
	if(! -e "$ARGV[1]"){die "channel directory \"$ARGV[1]\" not found.";}
	if(! -d "$ARGV[1]"){die "\"$ARGV[1]\" not a directory.";}
	$channel=basename($ARGV[1]);
	$ENV{'JOCKEYCALL_CHANNEL'}=$ARGV[1];
	# Any parameters to "transmit" subcommand will be after the channel
	# directory.
	my $parameter=$ARGV[2];
}else{
	if($ENV{'JOCKEYCALL_CHANNEL'} eq ''){Utility::usage; exit 0;}
	if(! -e "$ENV{'JOCKEYCALL_CHANNEL'}"){die "channel directory \"$ENV{'JOCKEYCALL_CHANNEL'}\" not found.";}
	if(! -d "$ENV{'JOCKEYCALL_CHANNEL'}"){die "\"$ENV{'JOCKEYCALL_CHANNEL'}\" not a directory.";}
	$channel=basename($ENV{'JOCKEYCALL_CHANNEL'}); 
	# Any parameters to subcommands other than "transmit" will be right
	# after the subcommand name.
	my $parameter=$ARGV[1];
}

# So, that ezstream wackiness above ... here's where we deal with it in an
# ungraceful way.
# 
# - Due to ezstream limitations regarding calling external programs for
#   playlist selection and metadata retrieval, it's necessary to use the
#   script filename as a way for ezstream to express what it wants when it
#   calls back in for those things.
#
# So basically: if the script name has certain things in it, then we pretend
# certain command line parameters were specified.  
#
if(index($0,'ezstream-intake-call')!=-1)
{
	$command='next';
	$parameter=$ARGV[0];
}
if(index($0,'ezstream-metadata-call')!=-1)
{
	$command='ezstream-metadata-provider';
	$parameter=$ARGV[0];
}

Conf::read_jockeycallconf(basename($0));
if($Conf::conf{'valid'}!=1){exit 1;}
Conf::read_conf($ENV{'JOCKEYCALL_CHANNEL'}."/config");
if($Conf::conf{'valid'}!=1){exit 1;}

# Debug messaging setup
Debug::debug_message_management(1,$Conf::conf{'basedir'}.'/'.$Conf::conf{'logs_at'},$channel);

Debug::debug_out "=== New Call [$channel $command] [$Conf::conf{'0'}] ===";

# If no command was specified earlier, notify user one is needed.
if($command eq '')
{
	Concurrency::fail(
	"channel $channel, path $ENV{'JOCKEYCALL_CHANNEL'}, caller $0\nYep, that's a valid channel with no configuration errors.\nSpecify a subcommand if you want me to do something.",2
	);
}

# Add Events module
use Events;

# Then tell Events module where the intermission directory is at.
# Would prefer for Events module to access this variable directly. 
#	Seems like modules can't access "our" vars in other modules. 
#	Tried it did not work.  Hence this workaround.
#
# $inm is also used later in main.
$inm=$Conf::conf{'basedir'}.'/'.$Conf::conf{'intermission_at'};
Events::set_inm($inm); # ::Events

# Tell IO module where to write play log files.
DataMoving::set_private_playlog_file($Conf::conf{'basedir'}.'/'.$Conf::conf{'logs_at'}.'/private-playlog-'.$channel.'-'.$Debug::timestamp.'.txt');
DataMoving::set_public_playlog_file($Conf::conf{'basedir'}.'/'.$Conf::conf{'logs_at'}.'/public-playlog-'.$channel.'-'.$Debug::timestamp.'.txt');

# Prepare lock code (or fail)
$Concurrency::concurrency_lock_code=qx\cat "/proc/sys/kernel/random/uuid"\;
if(($?!='0')or($Concurrency::concurrency_lock_code eq '')){Concurrency::fail "lock code generation failed, error code $?";}
Debug::debug_out "lock code is $Concurrency::concurrency_lock_code";

# TESTMODE, if enabled, will report in compact form what track is selected
# and also allow datestring to be specified in command line.
$TESTMODE=0;
$TESTMODE_datestring;

# Tell BannerUpdate module where our channel lives so it can get banners and
# channel information.
use BannerUpdate;
BannerUpdate::set_channel($channel,$Conf::conf{'basedir'});

# Take care of any subcommands other than 'next'.
# Subcomannds can acquire lock if needed.
use HTMLSchedule;
use Subcommands;
Subcommands::process_subcommand_other_than_next($channel,$command,$parameter);

# Secret option - presence of this parameter allows forcing a banner update
# manually from the command line.
#if(){BannerUpdate::set_doUpdate_flag();}


# Looking like we might actually do something productive.
# Good time to acquire lock (or fail).
if(!Concurrency::acquire_lock){technical_difficulties; Concurrency::succeed;exit 0;}


# Take care of any pending OOB delete requests.
use OOB;
OOB::set_channel($channel);
OOB::set_obq($Conf::conf{'basedir'}."/".$Conf::conf{'oob_queue_at'});
OOB::oob_pending_delete();

# Deliver from OOB queue if anything is there.
# No return from this point if there is something in the OOB queue.
OOB::oob_process_if_applicable();


# Prepare Operation module
use Operation;
Operation::set_channel($channel);


# Figure out current datestring.
if($TESTMODE==1)
# TESTMODE=1 means we get that from the command line.
{
	$datestring=$TESTMODE_datestring;
	debug_out "Test mode enabled - $TESTMODE_datestring"
}
else
{
# Otherwise it's derived from localtime.
	$datestring=strftime "1%H%M", localtime;
}

# Fetch datestring of previous call.
# Need to use root key (*_rkey() calls) until we determine a schedule
# directory.
$last_datestring=DataMoving::get_rkey('last-datestring',0);
DataMoving::set_rkey('last-datestring',$datestring);

Debug::debug_out "current datestring $datestring, last_datestring $last_datestring";

# --- New day check.
# Get current day number and day number of previous call.
@times=localtime; $currentday=$times[7];
$lastday=DataMoving::get_rkey('last-day',0);
DataMoving::set_rkey('last-day',$currentday);

# If current and previous day number are different, it's a new day.
if($lastday!=$currentday)
{
	Events::entering_new_day($currentday,$lastday);
}

# --- New DOW (day-of-the-week) check.
# Get current DOW number and DOW number of previous call.
$currentdow=$times[6];
$lastdow=DataMoving::get_rkey('last-day-of-week',$currentdow);
DataMoving::set_rkey('last-day-of-week',$currentdow);

# --- Check to see if we are in a new DOW.
# Don't check unless we are past the time where we consider the previous day
# to end.  This doesn't have to be at midnight.
if($datestring>$Conf::conf{'flip_day_at'})
{
        if($lastdow!=$currentdow)
        {
                Events::entering_new_dow($currentdow,$lastdow);
        }
}

# --- Span check.
# TODO

# --- Holiday check.
# TODO

# Point ourselves to the correct schedule directories.
if(!Conf::setdirs($currentdow))
 {technical_difficulties; succeed;exit 0;}

# Check for any channel-level periodics; if any, they will add to OOB queue.  
# Delivery of any found will start a little later below once we check for
# timeslot periodics.
my $channel_periodics_dir="$Conf::conf{'basedir'}/periodic";
if(-d $channel_periodics_dir)
{
	my $oob_flag=OOB::periodic_process($channel_periodics_dir,$last_datestring,$datestring);
}

# Prepare to read schedule.
my @schedule=();
# "zone" is how close we are to the end of the schedule.
# 0=green, 1=yellow: somewhat close, 2=red, pretty close
# Operation files will be ignored if zone is not green.
my $schedule_zone=0;

# NOTE: Used to be this:
# $scd="$Conf::conf{'basedir'}/$Conf::conf{'schedules_at'}";
# ...but instead we use $Conf::conf{'SCD'} - that is set by Conf::setdirs.
# This allows us to change the schedule directory according to specific days
# of the week, or even holidays.
$scd="$Conf::conf{'SCD'}";

# Actually read schedule
DataMoving::read_schedule_dir($scd,\@schedule);

# Dummy data so we can detect if these values have been modified or not.
$current_timeslot='zzzzz';
$next_timeslot='zzzzz';

# Empty schedule? Intermission then.
if(scalar(@schedule)==0)
{
	Debug::debug_out "schedule has no timeslots, going to intermission mode";
	goto INTERMISSION;
}

# Sort our retrieved schedule numerically.
my @schedule_sorted=sort{$a<=>$b} @schedule;

# Find which timeslot is equal or greater than current time.
# This determines which timeslot we currently should be selecting tracks
# from.
Debug::debug_out "scanning directories in $scd for appropriate timeslot";

# Set $current_timeslot to latest timeslot (-1 = end of array).
$current_timeslot=$schedule_sorted[-1];

# Why? 

# Search starts from current time to latest schedule.
# If search finds nothing, it won't be updated and we'll have the
# latest timeslot in $current_timeslot.
# This is the expected behavior.  

# Concrete example: it's 5am, and the earliest defined timeslot is 6am.
# There's a 11pm timeslot also defined.  At 5am we should still be
# playing the 11pm timeslot songs.

foreach $this_timeslot(@schedule_sorted)
{
	Debug::trace_out ".. \'$this_timeslot\' >= \'$datestring\' ?";
	last if($this_timeslot>=$datestring);
	$current_timeslot=$this_timeslot;
}
 
Debug::debug_out "this call is in timeslot $current_timeslot";
Debug::debug_out "scanning $scd for next timeslot";

$next_timeslot=0;

push @schedule_sorted,$schedule_sorted[0]+2400;
foreach $this_timeslot(@schedule_sorted)
{
	Debug::trace_out ".. \'$this_timeslot\' > \'$current_timeslot\' ?";
	$next_timeslot=$this_timeslot;
	last if($this_timeslot>$current_timeslot);
}

Debug::debug_out "next timeslot is $next_timeslot";

$difference=(Utility::datestring_to_minutes($next_timeslot)-Utility::datestring_to_minutes($datestring));
Debug::debug_out "$difference minutes until next schedule";

# Get record of the last timeslot we were in.
# This is needed to determine if we've moved into a new schedule (to restart
# history if desired)
my $in_last_timeslot=DataMoving::get_key("last_timeslot",'0');
my $last_timeslot=$in_last_timeslot;

Debug::debug_out "previous call was in timeslot $last_timeslot";
DataMoving::set_key("last_timeslot",$current_timeslot);

# Check for any timeslot-level periodics.
# Then, deliver from OOB queue if any found.
# This will also deliver channel-level periodics as well.
my $timeslot_periodics_dir="$Conf::conf{'SCD'}/$current_timeslot/periodic";
$oob_flag+=OOB::periodic_process($timeslot_periodics_dir,$last_datestring,$datestring);
if($oob_flag>0){OOB::oob_process_if_applicable();};

# Are we in a new timeslot?
my $FLAG_new_timeslot=0;
if($last_timeslot!=$current_timeslot)
{
	$FLAG_new_timeslot=1;
	Events::entering_new_timeslot();
	# clear timeslot history if we're entering a new one
	DataMoving::clear_object('timeslot-dir-history');
	DataMoving::set_key('timeslot-event-counter',1);
}
else
{
	$FLAG_new_timeslot=0;
	Debug::debug_out "still in same timeslot, using existing history";
	if(DataMoving::get_key('timeslot-event-counter','')<2)
	{
		if(($difference<$Conf::conf{'yellow_zone_mins'})and($difference>$Conf::conf{'red_zone_mins'}))
		{
		# yellow zone
		$schedule_zone=1;
		Operation::cancel_any_active
		DataMoving::set_key('timeslot-event-counter',2);
		Events::timeslot_zone($schedule_zone,$current_timeslot,$next_timeslot,$difference);	
		}
	}
	if(DataMoving::get_key('timeslot-event-counter','')==2)
	{
		if($difference<$Conf::conf{'red_zone_mins'})
		{
		# red zone
		$schedule_zone=2;
		Operation::cancel_any_active
		DataMoving::set_key('timeslot-event-counter',3);
		Events::timeslot_zone($schedule_zone,$current_timeslot,$next_timeslot,$difference);
		}
	}
}


my $close_to_edge_adjustment=0;
if(get_key('timeslot-event-counter','') eq 3)
{
	$oob_flag+=OOB::periodic_process($timeslot_periodics_dir.'/red-mark',$last_datestring,$datestring);
	if($oob_flag>0){OOB::oob_process_if_applicable();};
	$close_to_edge_adjustment=4;
}
if(get_key('timeslot-event-counter','') eq 2)
{
	$oob_flag+=OOB::periodic_process($timeslot_periodics_dir.'/yellow-mark',$last_datestring,$datestring);
	if($oob_flag>0){OOB::oob_process_if_applicable();};
}


# Timeslot directory contains one or more t-xxx-option-option-option
# directories.
# These allow the operator to control the behavior of track sets in the
# timeslot.
# So we will scan our timeslot directories and collect the ones that do not
# appear in the timeslot-dir-history list.

my @timeslot_dir_history=();
if($FLAG_new_timeslot==1)
{
	@timeslot_dir_history=DataMoving::set_key('timeslot-dir-history','');
	DataMoving::clear_object('timeslot-event-counter');
	Debug::debug_out "reset timeslot-dir-history";
}

ANOTHER_TIMESLOT_DIR:

@timeslot_dir_history=DataMoving::read_list("timeslot-dir-history","");
Debug::debug_out scalar(@timeslot_dir_history)." items in timeslot-dir-history";

my @current_timeslot_dirs=();
# Current timeslot directory
$tsd="$Conf::conf{'SCD'}/$current_timeslot";
# and tell BannerUpdate that too
BannerUpdate::set_timeslot($tsd);

# Check if something from a previous call wanted the banners to be flipped.
if(DataMoving::get_key('need-a-flip',0) eq '1')
{
	BannerUpdate::set_doUpdate_flag();
	DataMoving::clear_object('need-a-flip');
}

# Define random directory, based on current timeslot, as well.
$rdm=$tsd.'/random';

DataMoving::read_timeslot_dir($tsd,\@current_timeslot_dirs,\@timeslot_dir_history);

# Are all timeslot directories in history?
# This means we played through all of them.  So, time for intermission
# then.

if(scalar(@current_timeslot_dirs)==0)
{
	DataMoving::append_to_list("timeslot-dir-history",$tsd);
	Debug::debug_out "timeslot had no valid dirs, going to intermission";
	goto INTERMISSION;
}

# Sort it and lob the one off the top
my @current_timeslot_dirs_sorted=sort{$a cmp $b} @current_timeslot_dirs;
my $tsd=$current_timeslot_dirs_sorted[0];
Debug::trace_out "tsd is $tsd";

# Extract parameters of timeslot (part of timeslot directory name)\
$tsd_param_ordered=0;
$tsd_param_cycle=0;
$tsd_param_newhistory=0;
$tsd_param_limit=99999;
my @tsd_params=split /-/,$tsd;
# TODO: Handle this better.  Splitting $tsd on a dash could result in
# 2,3,4 not containing the expected parameters, if any directories have
# a dash in them.
if($tsd_params[2] eq 'ordered'){$tsd_param_ordered=1}
if($tsd_params[2] eq 'random'){$tsd_param_ordered=0}
if($tsd_params[3] eq 'cycle'){$tsd_param_cycle=1}
if($tsd_params[3] eq 'once'){$tsd_param_ordered=0}
if($tsd_params[4] eq 'newhistory'){$tsd_param_newhistory=1}
if($tsd_params[4] eq 'samehistory'){$tsd_param_newhistory=0}
if($tsd_params[5] ne ''){$tsd_param_limit=$tsd_params[5]};
if($tsd_param_limit eq 0){$tsd_param_limit=99999;}
Debug::trace_out " parameters: ordered=$tsd_param_ordered, cycle=$tsd_param_cycle, newhistory=$tsd_param_newhistory, limit=$tsd_param_limit";

# Restart history if desired
if(($FLAG_new_timeslot==1)and($tsd_param_newhistory==1))
{
	Debug::debug_out 'Starting new history';
	@timeslot_history=set_key('history','');
}
else
{
	Debug::debug_out 'Using existing history';
	@timeslot_history=read_list('history');
}
debug_out 'history has '.(scalar(@timeslot_history)).' entry(ies)';

# If we've played the limit number of tracks, we're done
if(scalar(@timeslot_history)>=$tsd_param_limit)
{
	Debug::debug_out 'At limit number of tracks';
	DataMoving::append_to_list('timeslot-dir-history',$tsd);
	goto ANOTHER_TIMESLOT_DIR;
}

TRY_AGAIN:

# Now read all entries within our selected timeslot and gather
# candidates for play selection.

# These arrays store data from timeslot and track metadata, as well as an
# array to reference track order.

my @t=(); # track
my @h=(); # hash
my @c=(); # play count
my @l=(); # time of last play
my @w=(); # weight

my @z=(); # order

$flag_dup=DataMoving::get_candidate_tracks($tsd,\@timeslot_history,\@t,\@h,\@c,\@l,\@w,\@z,abs($difference+$close_to_edge_adjustment),$schedule_zone);

Debug::debug_out "timeslot $current_timeslot has ".scalar(@t)." tracks not played yet.";

# Candidate list for this timeslot has no tracks?

# If $flag_dup is zero, then timeslot is empty or we don't have enough
# time to play any tracks in it.
if((scalar(@t)==0)and($flag_dup==0))
{
	DataMoving::append_to_list("timeslot-dir-history",$tsd);
	goto ANOTHER_TIMESLOT_DIR;
}
if((scalar(@t)==0)and($flag_dup!=0))
{
	if($tsd_param_cycle==0)
	{
		# if the option is "once" (not "cycle") ...
		# close out this timeslot dir by adding it to history, then circling
		# back to get the next one.
		DataMoving::append_to_list("timeslot-dir-history",$tsd);
		Operation::cancel_any_active();
		goto ANOTHER_TIMESLOT_DIR;
	}
	else
	{
  		# if the option is "cycle" (not "once") ...
		# clear history and try again.
		@timeslot_history=DataMoving::set_key("history","");
			goto TRY_AGAIN;
	}
}

# at this point, no more chance of being in intermission mode

# Check OOB queue in case something was just added.
# No return from this point if there is something in the OOB queue.
OOB::oob_process_if_applicable();

# Any active operations, we can go ahead and do the next step here.
# No return from this point if an operation is in progress.
# Any possible information the operation may need about the timeslot should be
# available.
Operation::process_any_active();

# set the mode to normal - handle intermission-normal transition here
$last_mode='unknown';
$current_mode=DataMoving::get_key('current-mode');
if($current_mode ne 'normal')
{
	if($last_mode='intermission')
	{
		$last_mode=$current_mode;
		$current_mode='normal';
		DataMoving::set_key('current-mode',$current_mode);
		Events::leaving_intermission()
	}
	else
	{
		$last_mode=$current_mode;
		$current_mode='normal';
		DataMoving::set_key('current-mode',$current_mode);
	}
}

if($tsd_param_ordered!=1)
{
	# Sort @z references in order of @c (play count).
	# Least played tracks will start at 1.
	my $size=(@z)+1; my $min=0;
	for($i=1;$i<$size;$i=$i+1){
	 for($j=$i+1;$j<$size;$j=$j+1){
	  if($c[$z[$j]]<$c[$z[$i]]){
	   $min=$z[$j]; $z[$j]=$z[$i]; $z[$i]=$min;
	   } } }
}

if($tsd_param_ordered==1)
{
	# Sort @z references in order of @t (track name).
	# Earliest in alphabet will be 1.
	my $size=(@z)+1; my $min=0;
	for($i=1;$i<$size;$i=$i+1){
	 for($j=$i+1;$j<$size;$j=$j+1){
	  if($t[$z[$j]] lt $t[$z[$i]]){
	   $min=$z[$j]; $z[$j]=$z[$i]; $z[$i]=$min;
	   } } }
}

Debug::trace_out "SORTED ===============================================================\n";
for(my $i=1;$i<=scalar(@t);$i++){Debug::trace_out $c[$z[$i]]."\t\t".$t[$z[$i]]."\n";}
Debug::trace_out "SORTED ===============================================================\n";

if($tsd_param_ordered!=1)
{
	# Pick a track randomly.
	$distribution=int(rand(100));
	if($distribution>75)
	{
		# 25% of time, pick any track.
		$max=scalar(@t);
	}
	else
	{
		# 75% of time, pick from the "bottom third" least played.
		$max=int(scalar(@t)/3);
	}
	$chosen_track=int(rand($max))+1;
}

if($tsd_param_ordered==1)
{
	# Very simple
	$chosen_track=1;
}

Debug::debug_out 'selected track '.$chosen_track.': '.$t[$z[$chosen_track]];

DataMoving::set_metadata($h[$z[$chosen_track]],'c:'.($c[$z[$chosen_track]]+1).'/l:'.$l[$z[$chosen_track]].'/w:'.$w[$z[$chosen_track]]);

DataMoving::append_to_list('history',$h[$z[$chosen_track]]);

DeliverTrack::now_play("$tsd/$t[$z[$chosen_track]]",'',0);

Concurrency::fail('DeliverTrack::now_play() returned for some reason.');
exit 1;

INTERMISSION:
# This point is reached (via goto, OMG) if we've played all tracks in
# the current timeslot, or various other conditions.

# If an operation is in progress, end it.
Operation::cancel_any_active();

# Prep BannerUpdate module
BannerUpdate::set_intermission_flag();
BannerUpdate::set_timeslot($inm);

# Check for any intermission periodics and deliver from OOB queue if any found
my $intermission_periodics_dir="$inm/periodic";
if(OOB::periodic_process($intermission_periodics_dir,$last_datestring,$datestring)>0){OOB::oob_process_if_applicable();};

INTERMISSION_RETRY:
# A history file is maintained for intermission slot,  Let's get it.
@intermission_history=read_list("intermission-history");
Debug::debug_out "intermission history has ".(scalar(@intermission_history))." entry(ies)";

# Now read all entries within intermission slot and gather candidiates
# for selection.

# These arrays store data from intermission slot and track metadata, as
# well as an array to reference track order.

my @t=(); # track
my @h=(); # hash
my @c=(); # play count
my @l=(); # time of last play
my @w=(); # weight

my @z=(); # order

$flag_dup=DataMoving::get_candidate_tracks($inm,\@intermission_history,\@t,\@h,\@c,\@l,\@w,\@z,99999,0);

Debug::debug_out "intermission slot $Conf::conf{'intermission_at'} has ".(scalar(@t))." candidate tracks.";

if(scalar(@t)==0)
{
	if($flag_dup==1)
	{
		Debug::debug_out "looks like we went through all intermission tracks, killing history and retrying ...";
		DataMoving::clear_object("intermission-history");
		goto INTERMISSION_RETRY;
	}
	else
	{
		Debug::error_out "intermission slot is empty";
		DeliverTrack::technical_difficulties();
	}
}

# at this point, we will definitely be picking an intermission track so
# so let's update the mode.
$last_mode='unknown';
$current_mode=DataMoving::get_key('current-mode');

if($current_mode ne "intermission")
{
	$last_mode=$current_mode;
	$current_mode="intermission";

	if($difference!=0)
	{
		my $difference1=$difference+1;
	}

	DataMoving::set_key("current-mode",$current_mode);
	DataMoving::clear_object('timeslot-event-counter');

	Events::entering_intermission();
}
else
{
	DataMoving::set_key("current-mode",$current_mode);
	DataMoving::clear_object('timeslot-event-counter');
}

# Sort @z references in order of @c (play count).
# Least played tracks will start at 1.
my $size=(@z)+1;
my $min=0;

for($i=1;$i<$size;$i=$i+1)
{
	for($j=$i+1;$j<$size;$j=$j+1){
	 if($c[$z[$j]]<$c[$z[$i]]){
	  $min=$z[$j];
	  $z[$j]=$z[$i];
	  $z[$i]=$min;
	  }
	 }
}

Debug::trace_out "SORTED ===============================================================\n";
for(my $i=1;$i<=scalar(@t);$i++)
{
	Debug::trace_out $c[$z[$i]]."\t\t".$t[$z[$i]]."\n";
}
Debug::trace_out "SORTED ===============================================================\n";

# Pick a track.
# If there is more than one track ...
if(scalar(@t)>1)
{
# ... then we pick one randomly.
# We might pick from all tracks or just the bottom half.
# (bottom half thing requires at least 3 tracks)
	my $previous_track=DataMoving::get_key("intermission-last-played-track");
	Debug::debug_out "previous track: $previous_track";
	$distribution=int(rand(100));
	if(($distribution>75)or(scalar(@t)<3))
	{
# 25% of time, pick any track.
# But: Do this no matter what if the number of tracks is less than 3.
		$max=scalar(@t);
	}
	else
	{
# 75% of time, pick from the "bottom half" least played.
		$max=int(scalar(@t)/2);
	}
# Make sure it doesn't match last track.
	while(42)
	{
		$chosen_track=int(rand($max))+1;
		next if($h[$z[$chosen_track]] eq $previous_track);
		last;
	}
}
else
{
	$chosen_track=1;
}

Debug::debug_out "selected intermission track ".$chosen_track.": $t[$z[$chosen_track]], $h[$z[$chosen_track]]";

DataMoving::set_metadata($h[$z[$chosen_track]],"c:".($c[$z[$chosen_track]]+1)."/l:".$l[$z[$chosen_track]]."/w:".$w[$z[$chosen_track]]);
DataMoving::append_to_list("intermission-history",$h[$z[$chosen_track]]);
DataMoving::set_key("intermission-last-played-track",$h[$z[$chosen_track]]);

DeliverTrack::now_play($inm.'/'.$t[$z[$chosen_track]],"INTERMISSION",1);

Concurrency::fail("DeliverTrack::now_play() returned unexpectedly");

exit 1;

