package DataMoving;
use parent 'Exporter';
use POSIX qw(strftime);
use File::Path qw(make_path); # needed for make_path()
require 'Debug.pm';
require 'Concurrency.pm';

# Functions for dealing with persistent and external data
# Functions for writing to playlog files

our @EXPORT=qw(
	set_public_playlog_file
	set_private_playlog_file
	public_playlog_out
	private_playlog_out	
	get_candidate_tracks
	read_timeslot_dir
	read_schedule_dir
	read_file_string
	get_key
	set_key	
	get_rkey
	set_rkey
	append_to_list
	read_list
	clear_object
	get_metadata
	set_metadata
        );

# public play log file
our $public_playlog_file;

# private play log file
our $private_playlog_file;

sub set_public_playlog_file
{
	if($_[0] eq '')
	{
	}
	$public_playlog_file=$_[0];
}

sub set_private_playlog_file
{
	if($_[0] eq '')
	{
	}
	$private_playlog_file=$_[0];
}

sub public_playlog_out
{

# Parameters/info
#
# $_[0]: Text to output to public_playlog
#
	if($_[0] eq ''){return;}

	if($public_playlog_file ne '')
	{
		if(open(FHPL,'>>',$public_playlog_file))
		{
			print FHPL scalar(localtime).': '.$_[0]."\n";
			close FHPL;
		}
	}
}

sub private_playlog_out
{

# Parameters/info
#
# $_[0]: Text to output to public_playlog
#
        if($_[0] eq ''){return;}

        if($private_playlog_file ne '')
        {
                if(open(FHPL,'>>',$private_playlog_file))
                {
                        print FHPL scalar(localtime).': '.$_[0]."\n";
                        close FHPL;
                }
        }
}

sub track_filter
{
	# Paramters/info
	# $_[0]: track name
	# $_[1]: schedule zone, 0=green, 1=yellow, 2=red
	#        we don't want to return .opr files if in yellow or red zone.
	# 
	# returns 1 if OK, 0 if caller should skip

	if( (lc(substr($_[0],-4)) eq '.mp3') ){return 1;}
	# Approve other file types here.
	if( (lc(substr($_[0],-4)) eq '.opr') ) 
	{
		if($_[1]==0)
		{
			Debug::trace_out "*** track_filter() operation file \"".$_[0]."\" filtered due to current schedule zone not being green.";
			return 1;
		}
		return 0;
	}
	Debug::trace_out "*** track_filter() file \"".$_[0]."\" filtered as unknown type.";
	return 0;
}

sub get_candidate_tracks
{
	Debug::trace_out "*** get_candidate_tracks($_[0])";

	# Parameters/info
	#
	# $_[0]: Directory containing timeslot tracks
	# @{$_[1]}: History array
	# @{$_[2]}: t trackname
	# @{$_[3]}: h hash of track
	# @{$_[4]}: c play count
	# @{$_[5]}: l time of last play
	# @{$_[6]}: w weight
	# @{$_[7]}: z order
	# $_[8]: difference
	# $_[9]: schedule zone, 0=green, 1=yellow, 2=red
	#        we don't want to return .opr files if in yellow or red zone.
	#
	# Goes through a list of timeslot tracks, eliminates tracks that are
	#  found in a provided history array, and then pushes various data in
	#  provided arrays.
	#
	# The arrays can be then sorted using various criteria and then a used
	#  to select a track for delivery.
	#
	# Returns $flag_dup.  This is 0 if no tracks were eliminated because
	#  they were found in the history.  If no candidate tracks are returned
	#  at all, then $flag_dup being 0 means that no tracks will fit in the
	#  remaining time left in the timeslot.
	#
	my $trackdir="$_[0]";

        my $n=0;
        my $ct=0; my $cl=0; my $cw=0;
        my $flag_dup=0;

	opendir my $d,$trackdir or fail("opendir failed on $trackdir");

	while(my $f=readdir($d))
	{
		# Filter all tracks through this function
		if(track_filter($f,$_[9]))
		{

			my $hash=MetadataProcess::metadata_process("$trackdir/$f",\@{$_[1]},\$ct,\$cl,\$cw,\$flag_dup);
			next if($hash eq '0');
			# check if we would have enough time in this timeslot
			# to play this.
			# If time does not matter, such as for the
			#  intermission, 99999 should be used.
			if($cl>($_[8]*60))
			{
       	        		 Debug::trace_out
				 "disqualified $hash because it's ".($cl-($_[8]*60))." seconds longer than end of timeslot.";
				next;	
			}
			push @{$_[2]},$f;
			push @{$_[3]},$hash;
			push @{$_[4]},$c;
			push @{$_[5]},$l;
			push @{$_[6]},$w;
			push @{$_[7]},$n;
			Debug::trace_out("candidate track $n: $hash, $f, C:$ct, L:$cl, W:$cw");
			$n++;
		}
	}
	closedir $d;

	return $flag_dup;
}

sub read_timeslot_dir
{
Debug::trace_out "*** read_timeslot_dir($_[0],$_[1],$_[2])";

# Parameters/info
#
# $_[0]: Directory containing timeslot
# @{$_[1]}: Reference to array that should hold t-dirs from timeslots
# @{$_[2]}: Reference to array that holds timeslot directory history
#
# Reads the t-dirs in a timeslot directory and puts them in an array.
#
# If directory is found in timeslot directory history, it won't be pushed on
# @{$_[1])
#
	opendir my $d,"$_[0]" or fail("opendir failed on $_[0]");

	while(my $f=readdir($d))
	{
# Reject subdirs that don't start with 't-'
	        next if(substr($f,0,2) ne 't-');
# Reject files that aren't a directory
	        my $d1f="$_[0]/$f";
		next if(! -d $d1f);
	        if(grep( /^$d1f$/,@{$_[2]}))
		{
			next
		}
	        Debug::trace_out "push $d1f";
   		push @{$_[1]},"$d1f";
	}
	closedir $d;
	Debug::debug_out(scalar(@{$_[1]})." dir(s) found in $_[0]");
}

sub read_schedule_dir
{
Debug::trace_out "*** read_schedule_dir($_[0])";

# Parameters/info
#
# $_[0]: Directory containing schedule 
# @{$_[1]}: Reference to array that should hold timeslots from schedule
#
# Reads the timeslots in the schedule and puts them in an array
#
	opendir my $d,"$_[0]" or Concurrency::fail("unable to open \"$_[0]\"");
	while(my $f=readdir($d))
	{
	# Skip unwanted things
		next if($f eq '.'); next if($f eq '..');
		next if(! -d "$_[0]/$f");
		next if(length($f)!=5); # if not 5 characters long
		next if(! $f =~ /^[:digit:]+/); # if not numeric
		push @{$_[1]},$f;
	}
	closedir $d;
	Debug::debug_out(scalar(@{$_[1]})." dir(s) found in $_[0]");
}

sub read_file_string
{
Debug::trace_out "*** read_file_string($_[0])";

# Parameters/info
#
# $_[0]: File to read, will NOT be created if it does not exist
# Returns text of key, or undef if key doesn't exist or an I/O error
# occurred.

	my $in_file="$_[0]";
	return undef if($in_file eq '');

	if(! -e $in_file)
	{
		Debug::trace_out "read_file_string($_[0]): file not found, returning undef";
		return undef;
	}
	
	open(my $f,'<',$in_file) or do{Debug::error_out "[read_file_string] unable to open $in_file for reading"; return "";};
	my $file_contents=<$f>;
	Debug::trace_out "read_file_string($_[0]): data \"$_[1]\"";
	close($f); chomp $file_contents; return $file_contents;
} 

sub get_key
{
	Debug::trace_out "*** get_key(\"$_[0]\",\"$_[1]\")";
	return $_[1] if($_[0] eq '');

# Parameters/info
#
# $_[0]: Key to read, will be created if it does not exist.
# $_[1]: Data to write, and return if file is empty.
#
# Returns text of key, or $_[1] if:
#  - key was new
#  - $_[0] was null
#  - an I/O error occurred and the key could not be read
#
# External variables used:
#  $Conf::conf{'VRD'}

	# Make key directory if needed	
	if(! -e "$Conf::conf{'VRD'}")
	{
		make_path($Conf::conf{'VRD'}) or do {Debug::error_out "[get_key] unable to make_path $Conf::conf{'VRD'}"; return $_[1];};
	}

	my $in_file="$Conf::conf{'VRD'}/$_[0].txt";
	
	if(! -e "$in_file")
	{
		open(my $f,'>',"$in_file") or do{Debug::error_out "[get_key] unable to open $in_file to write default value"; return $_[1];};
		Debug::trace_out "get_key($_[0]): new key written with default value \"$_[1]\"";
		print $f "$_[1]";
		close($f);
		return $_[1];
	}

	open(my $f,'<',"$in_file") or do{Debug::error_out "[get_key] unable to open $in_file for reading"; return $_[1];};
	my $file_contents=<$f>;
	Debug::trace_out "get_key($_[0]): existing key data \"$file_contents\"";
	close($f);
	chomp $file_contents;
	return $file_contents;
}


sub get_rkey
{
	Debug::trace_out "*** get_rkey(\"$_[0]\",\"$_[1]\")";
	return $_[1] if($_[0] eq '');

# Parameters/info
#
# $_[0]: Root key to read, will be created if it does not exist.
# $_[1]: Data to write, and return if file is empty.
#
# Returns text of key, or $_[1] if:
#  - root key was new
#  - $_[0] was null
#  - an I/O error occurred and the key could not be read
#
# External variables used:
#  $Conf::conf{'VRD'}

        # Make key directory if needed
        if(! -e "$Conf::conf{'basedir'}/$Conf::conf{'vars_at'}")
        {
                make_path($Conf::conf{'basedir'}/$Conf::conf{'vars_at'}) or do {Debug::error_out "[get_rkey] unable to make_path $Conf::conf{'VRD'}/$Conf::conf{'vars_at'}"; return $_[1];};
        }

	my $in_file="$Conf::conf{'basedir'}/$Conf::conf{'vars_at'}/$_[0].txt";
	
	if(! -e "$in_file")
	{
		open(my $f,'>',"$in_file") or do{Debug::error_out "[get_rkey] unable to open $in_file to write default value"; return $_[1];};
		Debug::trace_out "get_rkey($_[0]): new root key written with default value \"$_[1]\"";
		print $f "$_[1]";
		close($f);
		return $_[1];
	}

	open(my $f,'<',"$in_file") or do{Debug::error_out "[get_rkey] unable to open $in_file for reading"; return $_[1];};
	my $file_contents=<$f>;
	Debug::trace_out "get_rkey($_[0]): existing root key data \"$file_contents\"";
	close($f);
	chomp $file_contents;
	return $file_contents;
}


sub set_key
{
	Debug::trace_out "*** set_key(\"$_[0]\",\"$_[1]\")";
	return 0 if($_[0] eq '');

# Parameters/info
#
# $_[0]: Key to write to
# $_[1]: String to write
#
# Writing "" will clear the key
#
# Returns 1 if successful, 0 if an I/O error occurred
#
# External variables used:
#  $Conf::conf{'VRD'}

        # Make key directory if needed
        if(! -e $Conf::conf{'VRD'})
        {
                make_path($Conf::conf{'VRD'}) or do {Debug::error_out "    [set_key] unable to make_path \"$Conf::conf{'VRD'}\""; return $_[1];};
        }

	my $in_file="$Conf::conf{'VRD'}/$_[0].txt";

	open(my $f,'>',"$in_file") or do{Debug::error_out"    [set_key] unable to open $in_file for writing"; return 0;};
	print $f "$_[1]";
	close($f);

	return 1;
}


sub set_rkey
{
	Debug::trace_out "*** set_rkey(\"$_[0]\",\"$_[1]\")";
	return 0 if($_[0] eq '');

# Parameters/info
#
# $_[0]: Root key to write to
# $_[1]: String to write
#
# Writing "" will clear the root key
#
# Returns 1 if successful, 0 if an I/O error occurred
#
# External variables used:
#  $Conf::conf{'basedir'}, $Conf::conf{'vars_at'}

        # Make key directory if needed
        if(! -e "$Conf::conf{'basedir'}/$Conf::conf{'vars_at'}")
        {
                make_path($Conf::conf{'basedir'}/$Conf::conf{'vars_at'}) or do {Debug::error_out "    [set_rkey] unable to make_path $Conf::conf{'basedir'}/$Conf::conf{'vars_at'}"; return $_[1];};
        }

	my $in_file="$Conf::conf{'basedir'}/$Conf::conf{'vars_at'}/$_[0].txt";

	open(my $f,'>',"$in_file") or do{Debug::error_out"    [set_rkey] unable to open rkey $in_file for writing"; return 0;};
	print $f "$_[1]";
	close($f);

	return 1;
}


sub clear_rkey
{
	Debug::trace_out "*** clear_rkey(\"$_[0]\")";
	return 0 if($_[0] eq '');

        # Make key directory if needed
	# Even though we are clearing a key, we still need the directory there
	# for future use.
        if(! -e "$Conf::conf{'basedir'}/$Conf::conf{'vars_at'}")
        {
                make_path($Conf::conf{'basedir'}/$Conf::conf{'vars_at'}) or do {Debug::error_out "    [clear_rkey] unable to make_path $Conf::conf{'basedir'}/$Conf::conf{'vars_at'}"; return $_[1];};
	}

	my $in_file="$Conf::conf{'basedir'}/$Conf::conf{'vars_at'}/$_[0].txt";
	if(! -e $in_file){return 1;}

	open(my $f,'>',"$in_file") or do{Debug::error_out"    [clear_rkey] unable to open rkey $in_file for writing"; return 0;};
	print $f "";
	close($f);

	return 1;
}

sub append_to_list
{
	Debug::trace_out "*** append_to_list(\"$_[0]\",\"$_[1]\")";
	return 0 if($_[0] eq '');
	return 1 if($_[1] eq '');

# Parameters/info
#
# $_[0]: Key to append to
# $_[1]: String to append
#
# Returns 1 if successful, 0 if an I/O error occurred
#
# External variables used:
#  $Conf::conf{'VRD'}

	my $in_file="$Conf::conf{'VRD'}/$_[0].txt";
	open(my $f,'>>',"$in_file") or do{Debug::error_out "    [append_to_list] unable to open $in_file for append"; return 0;};
	print $f "$_[1]\n";
	close($f);

	return 1;
}

sub read_list{
	Debug::trace_out "*** read_list(\"$_[0]\")";

# Parameters/info
#
# $_[0]: List to read, will be created if it does not exist.
# Returns array of lines in list.
#
# Returns undef if list is empty or an I/O error occurred.
#
# External variables used:
#  $Conf::conf{'VRD'}

	my $in_file="$Conf::conf{'VRD'}/$_[0].txt";

	if(! -e $in_file)
	{
		open(my $f,'>',$in_file)or do{Debug::error_out "    [read_list($_[0])] unable to open $in_file for wrtiting (new list)"; return @empty_list=undef;};
		Debug::trace_out "    [read_list($_[0])] new list (empty)";
		print $f "";
		close($f);
		return my @empty_list=undef;
	}

	open(my $f,'<',$in_file)or do{Debug::error_out "    [read_list($_[0])] unable to open $in_file for reading"; return @empty_list=undef;};
	chomp(my @lines_of_data=<$f>);
	Debug::trace_out "    [read_list($_[0])] existing list ".scalar(@lines_of_data)." lines";
	close($f);
	return @lines_of_data;
}

sub clear_object
{
	Debug::trace_out "*** clear_object($_[0])";
	return 1 if($_[0] eq '');

# Parameters/info
#
# $_[0]: Key to clear, will be created if it does not exist
#
# Returns 1 if successful, 0 if I/O error
#
# External variables used:
#  $Conf::conf{'VRD'}

	my $in_file="$Conf::conf{'VRD'}/$_[0].txt";
	open(my $f,'>',"$in_file")or do{Debug::error_out "    [clear_object] unable to open $in_file for writing"; return 0;};
	print $f "";
	close($f);
	
	return 1;
}

sub get_metadata
{
	Debug::trace_out "*** get_metadata($_[0])";

# Parameters/info
#
# $_[0]: md5
#
# Returns null if an I/O error occurred.
#
# External variables used:
#  $Conf::conf{'basedir'}, $Conf::conf{'metadatadir'}

# TODO: Improve I/O error handling
	my $metadata;
	my $in_file="$Conf::conf{'basedir'}/$Conf::conf{'metadatadir'}/$_[0].txt";
	if(! -e $in_file)
	{
		my $new_data="c:0/l:0/w:0";
		Debug::trace_out "    [get_metadata($_[0])] new metadata object data \"$new_data\"";
		set_metadata($_[0],$new_data);
		return $new_data
	}
	open(my $m,'<',$in_file) or do{Debug::error_out "    [get_metadata($_[0])] unable to open $in_file for reading"; return "";};
	my $file_input=<$m>;
	Debug::trace_out "    [get_metadata($_[0])] existing metadata object data \"$file_input\"";
# TODO validate file input
	close $m;
	$metadata=$file_input;
	return $metadata;
}

sub set_metadata
{
	Debug::trace_out "*** set_metadata($_[0],\"$_[1]\")";

# Parameters/info
#
# $_[0]: md5
# $_[1]: data to write
#
# Returns 1 if written successfully, 0 if an I/O error occurred
#
# External variables used:
#  $Conf::conf{'basedir'}, $Conf::conf{'metadatadir'}

	my $in_file="$Conf::conf{'basedir'}/$Conf::conf{'metadatadir'}/$_[0].txt";

	open(my $m,'>',$in_file) or do{Debug::error_out "    [set_metadata($_[0],\"$_[1]\")] unable to open $in_file for writing"; return 1;};
	# TODO error handling
	print $m "$_[1]";
	close $m;

	return 0;
}

1;

