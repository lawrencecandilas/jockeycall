package OOB;
use List::Util qw/shuffle/;
use parent 'Exporter';
require 'Debug.pm';
require 'Conf.pm';
require 'Concurrency.pm';
require 'DataMoving.pm';
require 'DeliverTrack.pm';
require 'Utility.pm';

# Out of band queue management and processing

# What is the OOB queue?
# OOB queue is a place to put tracks that need to be played outside of
# the current timeslot.  Periodics use this.

# Channel, main shold set this
our $channel;

# Location of OOB queue
# main should tell us what this is, see below.
our $obq;

# This is needed because I can't figure out how to get %Conf::conf accessible
# to functions within OOB.pm.  Doesn't seem to work even if fully qualified.
# main calls this right after 'use OOB'.
sub set_channel
{
	$channel=$_[0];
}

# This is needed because I can't figure out how to get %Conf::conf accessible
# to functions within OOB.pm.  Doesn't seem to work even if fully qualified.
# main calls this right after 'use OOB'.
sub set_obq
{
	$obq=$_[0];
}

our $next;

sub oob_pending_delete
{
	Debug::trace_out "*** oob_pending_delete()";

# Process any pending delete request from a previous call.
# Will deliver technical difficulties track if it fails
	my $delete_this=DataMoving::get_rkey("delete-on-next-call");
	if($delete_this ne "")
	{
		# TODO: Security checks.
		Debug::debug_out "delete-on-next-call \"$delete_this\"";
		qx/rm -f "$delete_this"/;
		if($?!=0)
		{
			Debug::debug_out "delete-on-next-call \"$delete_this\" failed";
			DeliverTrack::technical_difficulties;
		}
		else
		{
			DataMoving::clear_rkey("delete-on-next-call");
		}
	}
}

sub oob_process_if_applicable
{
	Debug::trace_out "*** oob_process_if_applicable";
	if($obq eq '')
	{
		Debug::error_out "Shouldn't happen but did: obq is null";
		return 0;
	}
	if($channel eq '')
	{
		Debug::error_out '$channel is null.';
		$channel='a jockeycall channel';
	}

# Reads OOB queue and if a track is pending, will deliver it.
# Returns if no OOB track needed to be delivered.

# Read all tracks in OOB queue.
# Valid tracks in OOB queue must be in the format "oob-X-trackname".
# X is a numeric (001, 002, etc.) that determines the order.

	@oob_queue=();

	if(!opendir my $d,$obq){
		Debug::error_out "can't open oob_queue_dir \"$obq\"";
		Debug::error_out "OOB queue is getting ignored this call";
	}
	else
	{
		while(my $f=readdir($d))
		{
# OOB tracks must start with 'oob-'
		next if(substr($f,0,4) ne 'oob-');
# ... they must be a file
		next if(-d "$obq/$f");
# ... and element X in oob-X-etc must be numeric and not 0
# TODO: Test if numeric
		next if((split /-/,$f)[1]==0);
		push @oob_queue,$f;
		}
	closedir $d;
	}

# Sort OOB queue and use sorted queue to set $next ...
# If we want to add a track to the OOB queue, $next is the next free number

	my @oob_queue_sorted;

	if(scalar(@oob_queue)==0)
	{
# But do nothing if OOB queue is empty
		Debug::debug_out "OOB queue empty";
		$next=100;
	}
	else
	{
# Otherwise, let's sort it.
		Debug::debug_out "OOB queue has ".scalar(@oob_queue)." item(s)";
		@oob_queue_sorted=sort{$a cmp $b} @oob_queue;
		$next=((split /-/,$oob_queue_sorted[0])[1])-1;
	}

# $next is what number to assign new tracks ...
# Numbers start at a high value and work downward.
# (Lowest numbered tracks are played first.  OOB queue is a FIFO.)
	Debug::debug_out '$OOB::next is '.$next."\n";

# We now have a sorted, non-empty OOB queue,

# At this point we want to play an OOB track.

# Hopefully we do not encounter problems reading OOB queue files, but
# we set up a loop just in case.  We want to play the first one that
# passes check_track().

	while(scalar(@oob_queue_sorted)!=0)
	{
		my $temp=pop @oob_queue_sorted;
		my $oob_track="$Conf::conf{'basedir'}/$Conf::conf{'oob_queue_at'}/$temp";

		if(!DeliverTrack::check_track("$oob_track"))
		{
		Debug::error_out "check_track() failed on OOB track \"$oob_track\"";
		Debug::error_out "skipping this OOB track";
		next;
	}

# OOB tracks are actually removed from the queue on the subsequent
# call.
# Funny thing is I didn't put this in at first, and was wondering why
# all OOB tracks were coming up as file-not-found ... Derp.

		DataMoving::set_rkey("delete-on-next-call","$oob_track");
		Debug::debug_out "delete-on-next-call \"$oob_track\"";

# Tracks can have these strings in their names to hide their titles from
# Icecast.

		my $extra='';
		if(index($oob_track,"ZZ-COMMERCIAL-ZZ")!=-1){$extra="This is $channel - Commercial Break";}
		if(index($oob_track,"ZZ-STATION-ID-ZZ")!=-1){$extra="This is $channel - Station Identification";}
		if(index($oob_track,"ZZ-SILENCE----ZZ")!=-1){$extra="This is $channel";}
		if(index($oob_track,"ZZ------------ZZ")!=-1){$extra="This is $channel";}

		DeliverTrack::now_play($oob_track,$extra,1);

	} # while ...

}

sub oob_push
{
	Debug::trace_out "*** oob_push(\"$_[0]\"), next=$next";
	my $srcfile=$_[0]; my $destfile=$_[1];

	Debug::trace_out "oob_push(): $srcfile to $destfile";
	if(! -e "$srcfile"){return 0;}
	if(-e "$destfile"){return 1;}
	@result=qx/ln -s "$srcfile" "$destfile"/;
	Debug::debug_out "oob_push() result: $result[0]";
	$next--;
	return 1;
}

1;

sub interval_process
{
	Debug::trace_out "*** interval_process(\"$_[0]\")";

# Parameters/info
#
# $_[0]: Full path of an interval subdirectory.
# Example: /topdir/channel-name/periodic/15 ...
#          /topdir/channel-name/schedule/12345/periodic/15 ...
#
# Returns 0 if no tracks added to OOB queue, 1 if they were.

# An interval subdirectory will have one or more subdirectories that
# are tracklists.
#
# We want to gather a list of those tracks.
#
	my $in_interval_dir=$_[0];
	my @interval_tracklist_dirs=();

	Debug::trace_out "interval_process(): looking for tracklist subdirs in $in_interval_dir ...";

	opendir my $d,$in_interval_dir;
	while(my $f=readdir($d))
	{
		Debug::debug_out "interval_process(): $in_interval_dir/$f ?";
# Reject subdirs that don't start with 'p-'
		next if(substr($f,0,2) ne 'p-');
# Reject files that aren't a directory
		next if(! -d "$in_interval_dir/$f");
		Debug::debug_out "interval_process(): $in_interval_dir/$f added to interval_tracklist_dirs";
		push @interval_tracklist_dirs,"$in_interval_dir/$f";
	}
	closedir $d;

# If this interval subdirectory has no tracklist entries, we bail
#
	if(scalar(@interval_tracklist_dirs)==0)
	{
		Debug::debug_out "interval_process() $in_interval_dir: has nothing valid";
		return 0;
	};

# Sort our tracklist directory list
	my @interval_tracklist_dirs_sorted=sort{$a cmp $b} @interval_tracklist_dirs;

# Process tracklist directory
	Debug::trace_out "interval_process(): processing each tracklist ...";

	foreach $tls(@interval_tracklist_dirs_sorted)
	{
		# parse directory name.
		my $tls_param_ordered=0;
		my $tls_param_length=-1;
		my $tls_param_eachonce=0;
		my @tls_params=split /-/,$tls;
		if($tls_params[2] eq 'ordered'){$tls_param_ordered=1;}
		if($tls_params[2] eq 'random'){$tls_param_ordered=0;}
		if($tls_params[3] eq 'all')
		{
			$tls_param_length=-1;
		}
		else
		{
			$tls_param_length=$tls_params[3];
    		}
		if($tls_params[4] eq 'eachonce'){$tls_param_eachonce=1;}
	
		# prepare to get list of tracks contained within this
		# subdirectory.
	
		my $this_tracklist=();
	
		opendir my $t2,"$tls";
		while(my $f=readdir($t2))
		{
			Debug::trace_out "--- --- $f ?";
# Reject . and ..
			next if($f eq '.'); next if($f eq '..');
# Reject directories
			next if (-d "$tls/$f");
			Debug::trace_out "--- --- $f might add to OOB queue";
			push @this_tracklist,"$f";
		}
# That's it for this subdirectory if no valid tracks
		if(scalar(@this_tracklist)==0)
		{
			Debug::debug_out "--- --- tracklist has nothing valid";
			next;
		}
		closedir $t2;
	
		my $limit=1;
		if($tls_param_length==-1)
		{
			$limit=scalar(@this_tracklist);
		}
		else
		{
			$limit=$tls_param_length;
		}
	
		my @this_tracklist_1=();
	
# ------- random
		if($tls_param_ordered==0)
		{
			Debug::trace_out "interval_process(): random";
			@this_tracklist_1=shuffle @this_tracklist;
		}

# ------- ordered
		if($tls_param_ordered==1)
		{
			Debug::trace_out "interval_process(): ordered";
			@this_tracklist_1=sort{$a cmp $b} @this_tracklist;
		}

# ------- all
		foreach $t3(@this_tracklist_1)
		{
			oob_push("$tls/$t3","$obq/oob-$next-$t3");
			$limit--; last if($limit==0);
		}

	} # foreach

	return 1;
}

sub periodic_process
{
	Debug::trace_out "*** periodic_process(\"$_[0]\",$_[1],$_[2])";
	my $in_last_datestring=$_[1];
	my $in_datestring=$_[2];

# Parameters/info
#
# For the provided periodic directory, it will call interval_process()
# for each interval that the current datestring has just entered.
#
# interval_process() will add tracks to the OOB queue.
#
# If tracks are added to the OOB queue, main routine should circle
# back to the OOB queue processing point and feed out an OOB track.
#
# $_[0]: Full path of periodic directory that contains interval
# subdirs.
# $_[1]: $last_datestring
# $_[2]: $datestring
#
# Returns 0 if no tracks added to OOB queue, 1 if they were.

	Debug::debug_out "Looking at intervals for periodics";
	my @periodics=();
	 
	if(! -e "$_[0]"){return 1;}
 
# let's get a list of subdirs in $_[0].
	my @subdirs=();
	my @rrsubdirs=();
	if(!opendir my $d,"$_[0]")
	{
		Debug::error_out "could not open \"$_[0]\"";
	}
	else
	{
		while(my $f=readdir($d))
		{
# ... must be a directory
			next if(! -d "$_[0]/$f");
    			push @subdirs,$f;
		}
	closedir $d;
	}
	
	my $rr;
# see if this periodic has any round-robins
	if(-e "$_[0]/rr")
	{
# increment and get round-robin counters for this interval
        my $rr=DataMoving::get_key("interval-$interval-rr",0);
        $rr=$rr+1; if($rr>4){$rr=1;}
        DataMoving::set_key("interval-$interval-rr",0);
# let's get a list of round-robin subdirs in $_[0]/rr.
		if(!opendir my $d,"$_[0]/rr")
		{
			Debug::error_out "could not open \"$_[0]\"";
		}
		else
		{
			while(my $f=readdir($d))
			{
# ... must be a directory
				next if(! -d "$_[0]/$f");
				push @subdirs,$f;
			}
			closedir $d;
		}
	}

# for each supported interval, see if we're in it.
# TODO: Introduce some tolerance.
	#print "last, current: $in_last_datestring, $in_datestring\n";
	foreach my $interval((2,3,5,6,10,12,15,20,30,40,60,120,240,480,720))
	{
		Debug::trace_out "interval $interval";
		my $t1=int((Utility::datestring_to_minutes($in_last_datestring)-3)/$interval);
		my $t2=int((Utility::datestring_to_minutes($in_datestring)-3)/$interval);
  
		if(($t2-$t1)==1)
		{
			Debug::debug_out "new $interval minute mark - scanning for periodics";

# force a banner flip every 20 mins
#
# Sets a key as a signal to main, that main needs to check.
#
# This is needed because it looks like this routine can be called before
# main tells BannerUpdate the current and next timeslot.  It might be a bug.
#
# So main will check this variable and handle that when convenient for it.
#
			if($interval==20)
			{
				Debug::debug_out "Setting need-a-flip flag";
				DataMoving::set_key('need-a-flip',1);
			}

			foreach my $subdir(@subdirs)
			{
	 			##Debug::debug_out "$subdir = $_[0]/$interval? ";	
				if($subdir eq "$interval")
				{
					##Debug::debug_out "Found periodic $_[0]/$interval";
					##print "Found periodic $_[0]/$interval\n";
					push @periodics,"$_[0]/$interval";
				}
			} # foreach my $subdir( ...

			if($rr!=0){
				foreach my $rrsubdir(@rrsubdirs)
				{
					if($subdir eq "$rr")
					{
						##Debug::debug_out "Found periodic $_[0]/$interval/$rr";
						##print "Found periodic $_[0]/$interval/$rr\n";
						push @periodics,"$_[0]/$interval/$rr";
					}
     			 	} # foreach my $rrsubdir( ... 
 			}

		} # if(($t2-$t1)==1) ...
    
	} # foreach my $interval(( ...

# Process any/all periodic interval subdirs we found

	my $FLAG_added_a_periodic=0;

	if(scalar(@periodics)!=0)
	{
		Debug::debug_out "Processing ".scalar(@periodics)." periodic interval subdirectories.";
		foreach my $periodic(@periodics)
		{
			$FLAG_added_a_periodic+=interval_process($periodic);
		}
	}
	else
	{
		Debug::debug_out "No periodic interval subdirectories to process.";
	}

	return $FLAG_added_a_periodic;
}

1;
