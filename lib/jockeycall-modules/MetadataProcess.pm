package MetadataProcess;
use parent 'Exporter';
require 'Debug.pm';
require 'Conf.pm';
require 'DataMoving_SQLite.pm';

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
# Converts $_[0], assumed to be a filename of a song, to a md5hash.
# Then retrieves metadata record for that md5hash, parses the records and
# distributes the values among the variables pointed to by references.
# A database would probably be much better.
#
# If md5hash is found in provided history, it returns without doing
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

	my $md5hash=main::md5_hex($_[0]);

	if(grep( /^$md5hash$/, @{$_[1]} ))
	{
		Debug::trace_out "track $md5hash: $_[0] found in history, skipped";
		${$_[5]}=1;
		return 0;
	}

# read metadata and extract play count (c), length in seconds (l),
# and weight (w) from it.

	my $flag_set_metadata=0;

	my %metadata=DataMoving::get_metadata($md5hash);

	my $cc=0;
	$cc=$metadata{'c'};
	my $cl=0;
	$cl=$metadata{'l'};
	my $cw=0;
	$cw=$metadata{'w'};

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

	${$_[2]}=$cc; ${$_[3]}=$cl; ${$_[4]}=$cw;

	%metadata=('c'=>$cc,'l'=>$cl,'w'=>$cw);
	DataMoving::set_metadata($md5hash,\%metadata)if($flag_set_metadata==1);

	return $md5hash;

}

1;

