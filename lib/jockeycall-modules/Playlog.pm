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

1;
