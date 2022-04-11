package MetadataProcess;
use parent 'Exporter';
require 'Debug.pm';
require 'Conf.pm';
require 'DataMoving.pm';

# Metadata process

our @EXPORT=qw(
	metadata_process
        );

sub metadata_process
{
	Debug::trace_out "*** metadata_process($_[0])";
	Conf::check_conf_metadatadir;
	return 0 if($_[0] eq '');
	return 0 if(-d "$_[0]");
	return 0 if($_[0] eq '.');
	return 0 if($_[0] eq '..');

# Parameters/info
#
# Converts $_[0], assumed to be a filename of a song, to a hash.
# Then retrieves metadata record for that hash, parses the records and
# distributes the values among the variables pointed to by references.
# A database would probably be much better.
#
# If hash is found in provided history, it returns without doing
# anything else except setting $_[5] to 1.
#
# $_[0]: full path of filename
# $_[1]: reference to array holding history
# $_[2]: modifiable reference that can hold c
# $_[3]: modifiable reference that can hold l
# $_[4]: modifiable reference that can hold w
# $_[5]: modifiable reference that can be set to 1 if found in history
#
# External variables used:
#  $Conf::conf{'basedir'}, $Conf::conf{'metadatadir'}
# qx calls:
#  ./mp3info-static-noncurses
#  (should be in same dir as jockeycall.pl)

	my $hash=main::md5_hex($_[0]);

	if(grep( /^$hash$/, @{$_[1]} ))
	{
		Debug::trace_out "track $hash: $_[0] found in history, skipped";
		${$_[5]}=1;
		return 0;
	}

# read metadata and extract play count (c), length in seconds (l),
# and weight (w) from it.

	my $flag_set_metadata=0;
	my $ct=0; my $cl=0; my $cw=0;
	my $metadata=DataMoving::get_metadata($hash);
	my @m=split /\//,$metadata;

	foreach my $mx(@m)
	{
		# c: play count
		if(substr($mx,0,2) eq 'c:'){$ct=substr($mx,2);}
		# l: length in seconds
		if(substr($mx,0,2) eq 'l:')
		{		
			$cl=substr($mx,2);
			if($cl==0)
			{
				Debug::trace_out "command is $Conf::conf{'jockeycall_bin_mp3info'} -p \"%S\" \"$_[0]\"";
				my $mp3info_result=qx/$Conf::conf{'jockeycall_bin_mp3info'} -p "%S" "$_[0]"/;
				chomp $mp3info_result;
				my $seconds=$mp3info_result;
				Debug::trace_out "(length $seconds seconds)";
				$cl=$seconds;
				$flag_set_metadata=1;
			}
		}

	# w: weight value
	if(substr($mx,0,2) eq 'w:'){$cw=substr($mx,2);}
	}

	${$_[2]}=$ct; ${$_[3]}=$cl; ${$_[4]}=$cw;
	DataMoving::set_metadata($hash,"c:$ct/l:$cl/w:$cl")if($flag_set_metadata==1);
	return $hash;

}

1;

