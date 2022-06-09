package Conf;
use Data::Dumper;
use File::Basename;
use parent 'Exporter';
require 'Utility.pm';
require 'Debug.pm';
# Cannot depend on DataMoving.pm or DataMoving_SQLite.pm!

# Configuration read, parse, assertions, and ownership (%Conf::conf)
# Also configuration definition
 
my %possible_channel_conf_item;
my $possible_global_conf_item;

# Hash that defines valid configuration options for channels
$possible_channel_conf_item{'subdir_wday_sun'}	='chanscheddir-required,mapto:subdir_wday0';
$possible_channel_conf_item{'subdir_wday_mon'}	='chanscheddir-required,mapto:subdir_wday1';
$possible_channel_conf_item{'subdir_wday_tue'}	='chanscheddir-required,mapto:subdir_wday2';
$possible_channel_conf_item{'subdir_wday_wed'}	='chanscheddir-required,mapto:subdir_wday3';
$possible_channel_conf_item{'subdir_wday_thu'}	='chanscheddir-required,mapto:subdir_wday4';
$possible_channel_conf_item{'subdir_wday_fri'}	='chanscheddir-required,mapto:subdir_wday5';
$possible_channel_conf_item{'subdir_wday_sat'}	='chanscheddir-required,mapto:subdir_wday6';
$possible_channel_conf_item{'day_flip_at'}	='time-optional';
$possible_channel_conf_item{'track_td'}		='chanfile-required';
$possible_channel_conf_item{'track_um'}		='chanfile-required';
$possible_channel_conf_item{'state_db'}		='dbnameanddir-required';
$possible_channel_conf_item{'metadata_db'}	='dbnameanddir-required';
$possible_channel_conf_item{'schedules_at'}	='chandir-required';
$possible_channel_conf_item{'intermission_at'}	='chandir-required';
$possible_channel_conf_item{'logs_at'}		='chandir-required';
$possible_channel_conf_item{'max_rr_slots'}	='number-optional,range:2-999';
$possible_channel_conf_item{'random_at'}	='chandir-optional';
$possible_channel_conf_item{'random_percent'}	='number-optional,range:0-100';
$possible_channel_conf_item{'yellow_zone_mins'}	='number-optional,range:1-60';
$possible_channel_conf_item{'red_zone_mins'}	='number-optional,range:1-60';
$possible_channel_conf_item{'deliver_type'}	='string-optional';
$possible_channel_conf_item{'deliver_command'}	='string-optional';
$possible_channel_conf_item{'deliver_wait'}	='boolean-optional';

# Hash that defines valid configuration options for global jockeycall.conf 
 $possible_global_conf_item{'jockeycall_bin_curl'}
						='exe-optional,nobannersifbad';
 $possible_global_conf_item{'jockeycall_bin_mp3info'}
						='exe-optional';
 $possible_global_conf_item{'jockeycall_bin_ezstream'}
						='exe-optional';
 $possible_global_conf_item{'jockeycall_banner_service_enabled'}
						='boolean-required';
 $possible_global_conf_item{'jockeycall_banner_base_path'}
						='dir-optional,nobannersifbad';
 $possible_global_conf_item{'jockeycall_banner_service_autoflip_every'}
						='number-optional,range:1-720';
 $possible_global_conf_item{'jockeycall_banner_service_url'}
						='url-optional,nobannersifbad';
 $possible_global_conf_item{'jockeycall_banner_service_key'}
						='string-optional,nobannersifbad';

# This holds the current config as read from files
our %conf;

# Validity flag.  If this is 0 after calling read routines, the configuration
# couldn't be read or there was a problem, and main should abort.
$conf{'valid'}=0;

# Location where we are running from - specifically `main`.
# `main` has to set this, not us.
# Used by `transmit` subcommand.
$conf{'mypath'}='.';

# This is 1 if banners should be disabled.  This can be true if explicitly
# specified by the config, or forced true if there is an error with banner
# related config items.
our $disable_banners=0;

# Name of this script that is running.
#
# This supports changing behvaior depending on the name of the script.
#
# read_jockeycallconf() sets this, which should be the first function called
# in this module and should be called very early by main.
$conf{'0'}='';

# Defaults for global config
$conf{'jockeycall_bin_curl'}='/usr/bin/curl';
$conf{'jockeycall_bin_mp3info'}='./mp3info-static-nocurses';
$conf{'jockeycall_bin_ezstream'}='/usr/local/bin/ezstream';
$conf{'jockeycall_banner_service_enabled'}=0;
$conf{'jockeycall_banner_service_autoflip_every'}=20;

# Defaults for channel-specific config
# Path is prefixed by 'schedules_at'
$conf{'subdir_wday_sun'}='normal/sunday';
$conf{'subdir_wday_mon'}='normal/weekday';
$conf{'subdir_wday_tue'}='normal/weekday';
$conf{'subdir_wday_wed'}='normal/weekday';
$conf{'subdir_wday_thu'}='normal/weekday';
$conf{'subdir_wday_fri'}='normal/weekday';
$conf{'subdir_wday_sat'}='normal/saturday';
# Default time that weekdays 'change'
$conf{'day_flip_at'}='10500';
# Holiday schedule subdirectories
$conf{'subdir_hday_0101'}='normal/weekday';
$conf{'subdir_hday_0214'}='normal/weekday';
$conf{'subdir_hday_0604'}='normal/weekday';
$conf{'subdir_hday_1124'}='normal/weekday';
$conf{'subdir_hday_1225'}='normal/weekday';
$conf{'subdir_hday_1231'}='normal/weekday';
# Maximum number of periodic interval round-robin slots
$conf{'max_rr_slots'}=16;
# Default random directory for entire channel
$conf{'random_at'}='';
# Default random_percent
$conf{'random_percent'}=97;
# Default schedule zone threshoolds
$conf{'yellow_zone_mins'}=12;
$conf{'red_zone_mins'}=8;
# Default track delivery options
$conf{'deliver_type'}='ezstream';
$conf{'deliver_command'}='echo "deliver_command test: requested track is \"%\", JOCKEYCALL_TRACK_SECONDS=$JOCKEYCALL_TRACK_SECONDS"';
$conf{'deliver_wait'}=0;

# Environment-controlled stuff
# On module instantiation, we'll pull in some environment variables,
# validate them, and copy them to conf vars.
#
# TODO: The validation above
$conf{'env_CHANNEL'}=$ENV{'JOCKEYCALL_CHANNEL'};
#
# JOCKEYCALL_TRACE should be 1 to enable trace messages.
$conf{'env_TRACE'}=$ENV{'JOCKEYCALL_TRACE'};


sub sift_conf_line
{
# Parameters/info
#
# $_[0]: Configuration line
#
# Utility function for configuration reading routines below.
#
# Returns array containing configuration item name as first element, and 
# configuration item value as second element.
#
# If line is blank or just a comment, both elements will be null.
#
# TODO: Might put some processing in here that deals with #'s trailing 
# the configuration value.  Currently not supported.
#
	my $confline=$_[0];
	my @confline=('','');

	$confline=~s/^\s+|\s+$//g;
	# blank lines are nothing
	return @confline if ($confline eq '');
	# lines beginning with # are comments
	return @confline if ($confline =~ /^\s*#/); 

	($confline[0],$confline[1])=split(' ',$confline,2);
	$confline[0]=lc($confline[0]);
	return @confline;
}


# These are set by setdirs() below.
#
$conf{'SCD'}='.';
# for flatfile
$conf{'VRD'}='.';

sub setdirs
{
# Parameters/info
#
# $_[0]: Numeric day of week (from localtime[6])
#
# Package-level variables used:
#  $conf{'basedir'},$conf{'subdir_wday'},$conf{'schedules_at'},
#  $conf{'vars_at'}
#  $conf{'progvarstable'}

	# Bounce if we get an invalid DOW for some reason.
	return 0
	 if(($_[0]>6)||($_[0]<0));
	
	my $temp=$conf{'subdir_wday'.$_[0]};

	$conf{'SCD'}="$conf{'basedir'}/$conf{'schedules_at'}/$temp";

	# for flatfiles
	$conf{'VRD'}="$conf{'basedir'}/$conf{'vars_at'}/$temp";

	return 1;
}


sub check_conf_basedir
{
#Debug::trace_out("*** check_conf_basedir($_[0])");
# Parameters/info
#
# Verify conf_basedir is defined and exists.
#
# Returns 1 if conf_basedir is OK, 0 if it is not.
#
# Package-level variables used:
#  $conf{'basedir'}

	if($conf{'basedir'} eq '')
	{
		Debug::conf_error_out("conf_basedir not defined.");
		return 0;
	}
	
	if(! -e "$conf{'basedir'}"){
		Debug::conf_error_out("conf_basedir directory \"$conf{'basedir'}\" not found");
		return 0;
	}

	return 1;
}


sub validate_and_set_conf_line
{
#
# Perform validation on one configuration line item.
#
# $_[0]: Configuration item name
# $_[1]: Configuration item value
# $_[2]: 1 if channel configuration, 0 if global configuration
# Returns 1 if OK, 0 if invalid
# 
# Package-level variables used:
#  %possible_channel_conf_item; %possible_global_conf_item
#
# Will report errors via Debug module.

	return 1 if($_[0] eq ''); # might be a blank line, not an error

	my $validator;
	if($_[2]==1)
	{
		$validator=$possible_channel_conf_item{$_[0]};
	}else{
		$validator=$possible_global_conf_item{$_[0]};
	}

	if($validator eq '')
	{
		Debug::conf_error_out "-- unknown configuration item \"".$_[1]."\" encountered";
		return 0;
	}

	# Time to chop up the validator for processing
	# - some validators MAY have 2 parts separated by commas
	my($validator_part1,$validator_part2)=split(',',$validator,2);

	# - the left part MUST always have 2 parts separated by dashs
	my($validator_type,$validator_need)=split('-',$validator_part1,2);

	# - if need is 'optional', then it's OK if value is blank.
	if(($_[1] eq '')&&($validator_need eq 'optional'))
	{
		return 1;
	}
	# - if need is 'required', then it's NOT OK if value is blank.
	if(($_[1] eq '')&&($validator_need eq 'required'))
	{
		Debug::conf_error_out "-- $_[0]: requires a value and one isn't specified.";
		return 0;
	}

	# - ... continuing with chopping up the validator
	#   the right part MAY have 2 parts separated by colons
	my($validator_qualifier,$validator_params)=split(':',$validator_part2,2);

	# - and the "validator_params" MAY have 2 parts separated by dashes
	my($validator_param1,$validator_param2)=split('-',$validator_params,2);

	# Ok, validator is chopped up.

	$validator_recognized=0;

	if(substr($validator_type,-3) eq 'dir')
	{
		$validator_recognized=1;
		my $dir_to_check;
		if($validator_type eq 'dir')		{$dir_to_check=$_[1];}
		if($validator_type eq 'chandir')	{$dir_to_check=$conf{'basedir'}.'/'.$_[1];}
		if($validator_type eq 'chanscheddir')	{$dir_to_check=$conf{'basedir'}.'/'.$conf{'schedules_at'}."/".$_[1];}
		if($validator_type eq 'dbnameanddir')
							{$dir_to_check=dirname($conf{'basedir'}.'/',$_[1]);}
		if(!(-d $dir_to_check))
		{
			if($validator_need eq 'optional'){return 1;} # nonexistence doesn't matter if optional
			if($validator_qualifier eq 'nobannersifbad')
			{
				$disable_banners=1;
				Debug::debug_out "-- $_[0]: \"".$dir_to_check."\" not found or not a directory - disabling banners";
				return 1;
			}else{
				Debug::conf_error_out "-- $_[0]: \"".$dir_to_check."\" not found or not a directory";
				return 0;
			}
		}
	}

	if($validator_type eq 'chanfile')
	{
		$validator_recognized=1;
		if(! -e $conf{'basedir'}.'/'.$_[1])
		{
			Debug::conf_error_out "-- $_[0]: \"".$_[1]."\" not found or inaccessible";
			return 0;
		}
	}

	if($validator_type eq 'url')
	{
		$validator_recognized=1;
		my $okflag=0;
		if(rindex($_[1],'https://')==0){$okflag=1;}
		if(rindex($_[1],'http://')==0){$okflag=1;}
		if(!$okflag)
		{
			Debug::conf_error_out "-- $_[0]: \"".$_[1]."\" isn't a valid URL";
			return 0;
		}
	}

	if($validator_type eq 'time')
	{
		$validator_recognized=1;
		if(!Utility::check_datestring($_[1]))
		{
			Debug::conf_error_out "-- $_[0]: \"".$_[1]."\" isn't a valid datestring 1HHMM";
			return 0;
		}
	}

	if($validator_type eq 'number')
	{
		$validator_recognized=1;
		if(!($_[1] =~ /^\d*$/))
		{
			Debug::conf_error_out "-- $_[0]: \"".$_[1]."\" has stuff other than digits in it";
		}
	        if($validator_qualifier eq 'range')
        	{
	                if(($_[1]<$validator_param1)||($_[1]>$validator_param2))
        	        {
                	        Debug::conf_error_out "-- $_[0]: $_[1] is out of the range $validator_param1-$validator_param2";
                        	return 0;
	                }
	        }
	}

	if($validator_type eq 'exe')
	{
		$validator_recognized=1;
		if(! -x $_[1])
		{
                        if($validator_qualifier eq 'nobannersifbad')
                        {
                                $disable_banners=1;
                                Debug::debug_out "-- $_[0]: \"".$_[1]."\" not found or not an executable file - disabling banners";
                                return 1;
                        }else{
				Debug::conf_error_out "-- $_[0]: \"".$_[1]."\" not found or not an executable file";
				return 0;
			}
		}
	}

	if($validator_type eq 'boolean')
	{
		$validator_recognized=1;
		if(($_[1] ne '0')&&($_[1] ne '1'))
		{
			Debug::conf_error_out "-- $_[0]: \"".$_[1]."\" isn't 0 or 1";
			return 0;
		}
	}

	if($validator_type eq 'string')
	{
		$validator_recognized=1;
	}

	if($validator_recognized==0)
	{
		Debug::conf_error_out "-- unrecognized validator type \"$_[0]\" - report this as a bug unless you modified the code";
		return 0;
	}

	if($validator_qualifier eq 'mapto')
	{
		$conf{$validator_param1}=$_[1];
	}
	else
	{
		$conf{$_[0]}=$_[1];
	}

	return 1;
}


sub read_jockeycallconf
{
#
# Read and parse global jockeycallconf configuraton file.
#
# Parameters/info
#
# $_[0]: Name of jockeycall script (e.g. basename($0))
#	
#       $conf{'0'} is the name of the script, can be checked by things that
#	want to change behavior depending on the name of the script.
#	This function should be called very early by main and before any
#	other function, really, so this is a good place to set $conf{'0'}.

	# So let's set that important $conf{'0'} right now.
	$conf{'0'}=$_[0];
	
	# And we use it right now as a matter of fact.
	# The name of this script will control where we look for the global
	# configuration file.
	my $jockeycallconf_file='/etc/jockeycall.conf';
	if($ENV{'JOCKEYCALL_CONF'} eq 'devel') {$jockeycallconf_file='../local/etc/jockeycall.conf';}
	if($ENV{'JOCKEYCALL_CONF'} eq 'opt')   {$jockeycallconf_file='/opt/jockeycall/etc/jockeycall.conf';}

	Debug::trace_out("expecting global config to be \"".$jockeycallconf_file."\"");

	# return with error if jockeycall.conf file doesn't exist 
	if(! -e $jockeycallconf_file)
	{
		Debug::conf_error_out("jockeycall.conf configuration file $jockeycallconf_file not found");
		Debug::conf_error_out('changing this involves the JOCKEYCALL_CONF environment variable');
		return 0;
	}

        open(my $jockeycallconf_file_handle,'<',$jockeycallconf_file); ##or fail "open of $jockeycallconf_file failed";

	my $conf_errors=0;
        while(<$jockeycallconf_file_handle>)
        {
                my $line=$_;
		$line=~s/^\s+|\s+$//g;

		next if($line eq ''); # skip blank lines
		next if($line =~ /^\s*#/); # skip lines beginning with # - comments

		# all configuration lines are a token, space, then value.
		# TODO: something to account for comments in the middle of lines
                my($first,$rest)=split(' ',$line,2);

                if(validate_and_set_conf_line($first,$rest,0)!=1){$conf_errors++;}
        }

#	print Dumper(\%conf);
        close($conf_file_handle);

# report any errors.
#
        if($conf_errors!=0)
        {
                Debug::conf_error_out "jockeycall.conf configuration failed validation, $conf_errors error(s)";
                return 0
        }
        else
        {
                $conf{'valid'}=1;
        }

# misc stuff
	if($conf{'jockeycall_banner_service_enabled'}=0){$banners_disabled=1;}

        return 1;
}


sub read_conf
{
	$conf{'valid'}=0;
	return 0 if($_[0] eq '');
# 
# Read and parse channel configuration file.
#
# Parameters/info
#
# $_[0]: Channel configuration file
#
# Package-level variables used:
#  $conf{'basedir'}

	my $conf_file=$_[0];

# check if configuration file even exists	
	if(! -e $conf_file)
	{
		Debug::conf_error_out("channel configuration file $conf_file not found");
		return 0;
	}

# At one point this was settable in configuration file but no longer.
# $Conf::conf{'basedir'} is simply the config file's dirname.

	$conf{'basedir'}=dirname($conf_file);

	open(my $conf_file_handle,'<',$conf_file); ##or fail "open of $conf_file failed";

	my $conf_errors=0;
	while(<$conf_file_handle>)
	{
		my $line=$_;
		my($first,$rest)=sift_conf_line($line);
		next if($first eq '');
		if(validate_and_set_conf_line($first,$rest,1)!=1){$conf_errors++;}
	}

	close($conf_file_handle);

# report any errors.
#
        if($conf_errors!=0)
        {
                Debug::conf_error_out "channel configuration failed validation, $conf_errors error(s)";
                return 0
        }
        else
        {
                $conf{'valid'}=1;
        }
	return 1;

}

1;

