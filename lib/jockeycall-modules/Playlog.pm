package Playlog;
use parent 'Exporter';
use POSIX qw(strftime);

# Functions for writing to playlog files

our @EXPORT=qw(
	set_public_playlog_file
	set_private_playlog_file
	public_playlog_out
	private_playlog_out	
        );

# public playlog file
our $public_playlog_file;

# private playlog file
our $private_playlog_file;

# this lets main set the log files from the configuration
sub set_public_playlog_file
{
	$public_playlog_file=$_[0];
}
sub set_private_playlog_file
{
	$private_playlog_file=$_[0];
}

sub public_playlog_out
{

# Parameters/info
#
# $_[0]: Text to output to public_playlog
#
	return if(($_[0] eq '')or($public_playlog_file eq ''));

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
# $_[0]: Text to output to private_playlog
#
# The private playlog will have the full paths to files and provide more
# information on schedule transitions.
#
        return if(($_[0] eq '')or($private_playlog_file eq ''));

        if($private_playlog_file ne '')
        {
                if(open(FHPL,'>>',$private_playlog_file))
                {
                        print FHPL scalar(localtime).': '.$_[0]."\n";
                        close FHPL;
                }
        }
}


1;
