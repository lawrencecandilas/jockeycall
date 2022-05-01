package ParamParse;
use File::Basename;
use parent 'Exporter';
require 'Debug.pm';
require 'Conf.pm';

# Functions called when specific things happen

our @EXPORT=qw(
	timeslot_dir_params
        );

sub periodic_portion_subdir_params
{
# $_[0]: incoming periodic portion subdirectory name
# Name is processed with File::Basename
#
# Returns hash containing parameters (that overwrite defaults in the hash)
#
# Periodic portion subdirectory format is this:
# p-NNN-x-x-...
#  p:	required
#  NNN:	Number identifying order.  Suggest to use 3 digits with
#       leading zeros, though any digits are OK.
#       - (Routine below will skip words until a number is found, then skip
#         the number, then process according to below)
#  x:	Word or digit.
#
# What is intended to be supported:
# t-NNN-{'ordered' OR 'random'}-{OPTIONAL NUMBER FOR length OR 'all'}
#
        my %out;
        $out{'ordered'}=0;
        $out{'limit'}=-1; # -1 means "all"

        my @params=split /-/,basename($_[0]);

        my $skipflag=0;
        foreach $param(@params)
        {
                if($param eq 'p')
                {
                        $skipflag=1;
                        next;
                }
                if(($skipflag==1)&&($param =~ /[[:digit:]]/))
                {
                        $skipflag=0;
                        next;
                }

                if($param eq 'ordered')         {$out{'ordered'}=1;	}
                if($param eq 'random')          {$out{'ordered'}=0;	}
                if($param eq 'all')		{$out{'limit'}=-1;	}
                if($param =~ /[[:digit:]]/)     {$out{'limit'}=$param;	}
        }

        return %out;
}


sub timeslot_portion_subdir_params
{
# $_[0]: incoming timeslot portion subdirectory name
# Name is processed with File::Basename
#
# Returns hash containing parameters (that overwrite defaults in the hash)
#
# Timeslot portion subdirectory format is this:
# t-NNN-x-x-...
#  t: 	required
#  NNN:	Number identifying order.  Suggest to use 3 digits with
#	leading zeros, though any digits are OK.
#	- (Routine below will skip words until a number is found, then skip
#	  the number, then process according to below)
#  x:	Word or digit.
#
# What is intended to be supported:
# t-NNN-{'ordered' OR 'random'}-{'cycle' OR 'once'}-{'newhistory' OR 'samehistory'}-{OPTIONAL NUMBER FOR limit}
#
	my %out;
	$out{'ordered'}=0;
	$out{'cycle'}=0;
	$out{'newhistory'}=1;
	$out{'limit'}=99999;

	my @params=split /-/,basename($_[0]);

	my $skipflag=0;
	foreach $param(@params)
	{
		if($param eq 't')
		{
			$skipflag=1;
			next;
		}
		if(($skipflag==1)&&($param =~ /[[:digit:]]/))
		{
			$skipflag=0;
			next;
		}

		if($param eq 'ordered')		{$out{'ordered'}=1;			}
		if($param eq 'random')		{$out{'ordered'}=0;			}
		if($param eq 'cycle')		{$out{'cycle'}=1;$out{'newhistory'}=0;	}
		if($param eq 'once')		{$out{'cycle'}=0;			}
		if($param eq 'newhistory')	{$out{'newhistory'}=1;			}
		if($param eq 'samehistory')	{$out{'newhistory'}=0;			}
		if($param =~ /[[:digit:]]/)	{$out{'limit'}=$param;			}
	}

	return %out;
}


1;
