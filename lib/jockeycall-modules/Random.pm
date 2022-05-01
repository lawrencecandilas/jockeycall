package Random;
require 'Debug.pm';
require 'Concurrency.pm';
require 'DataMoving.pm';
require 'Operation.pm';
use File::Basename;
use parent 'Exporter';

# Handles random feature

our @EXPORT=qw(
	);

# Where Random looks for tracks.
# Should be set externally by main ...
our %dir;

# ... using these convenient method.
sub set_channel_dir
{
	Debug::trace_out("*** Random::set_channel_dir(\"$_[0]\")");
	$dir{'channel'}=$_[0];
	return 1;
}

sub set_timeslot_dir
{
	Debug::trace_out("*** Random::set_timeslot_dir(\"$_[0]\")");
	$dir{'timeslot'}=$_[0];
	return 1;
}


sub get_random_track
{
        Debug::trace_out "*** Random::get_random_track(\"$_[0]\",$_[1],$_[2])";
# Parameters/info
#
# @{$_[0]}: History array
# $_[1]: difference
# $_[2]: schedule zone, 0=green, 1=yellow, 2=red
#        -1=intermission or other situation where we don't want .opr files
#
#        we don't want to return .opr files unless zone is green
#	 [right now -1 is always passed]
#
# Pulls all tracks in provided directories above, eliminates tracks that
# appear in a provided history array, then picks a random one if possible.
#
# Returns empty string if nothing can be chosen.
# External caller is likely main which will then continue with normal flow.
#
	my @candidate_random_tracks;
	foreach $which_random_dir(keys %dir)
	{	
		my $trackdir=$dir{$which_random_dir};	
		if($trackdir eq '')
		{
			Debug::error_out("[Random::get_random_track] no \"$which_random_dir\" directory set for random tracks");
			return '';
		}else{
			Debug::trace_out("    checking \"$which_random_dir\"'s directory \"$trackdir\" that was previously set for random tracks");
		}

       		opendir my $d,$trackdir
		or do{
			Debug::error_out("[Random::get_random_track] opendir failed on \"$trackdir\"");
			next;
		};
	
       	 	while(my $f=readdir($d))
       	 	{
       	        	# filter all tracks through this function
			# Passing -1 to track_filter - no operations should be
			# kicked off from random track pools just quite yet.
       	        	if(DataMoving::track_filter($f,-1))
       	        	{
				# get md5 hash of track
		       		my $md5hash=main::md5_hex($f);

				# skip if found in provided history array
				next if(grep( /^$md5hash$/, @{$_[0]} ));

                        	# check if we would have enough time in this
				# timeslot to play this.
                        	# If time does not matter, such as for the
                        	#  intermission, 99999 should be used.
				my %m=DataMoving::get_metadata($md5hash);
				if(%m=undef){next;}
                        	if(m{'l'}>($_[1]*60))
                        	{
                               		Debug::trace_out
                                	"    disqualified $md5hash because it's ".($cl-($_[8]*60))." seconds longer than end of timeslot.";
                                	next;
                        	}

				push @candidate_random_tracks,$f
       	        	}
		}
		close $d;
	}

	if(scalar(@candidate_random_tracks)==0)
	{
		Debug::trace_out("[Random::get_random_track] No tracks left in \"$_[0]\" after checking history");
		return '' 
	}

	if(scalar(@candidate_random_tracks)==1)
	{
		return $candidate_random_tracks[0];
	}

	return $candidate_random_tracks(int(rand(scalar(@candidate_random_tracks)))+1);
}


1;
