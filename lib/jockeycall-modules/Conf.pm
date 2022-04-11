package Conf;
use File::Basename;
use parent 'Exporter';
require 'Debug.pm';

# Configuration read, parse, assertions, and ownership (%Conf::conf)

our %conf;

# Validity flag.  If this is 0 after calling read routines, the configuration
# couldn't be read or there was a problem, and main should abort.
$conf{'valid'}=0;
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

$conf{'SCD'}='';
$conf{'VRD'}='';

# Default schedule subdirectories for days of the week
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

# Default random_percent
$conf{'random_percent'}=97;

# Default schedule zone threshoolds
$conf{'yellow_zone_mins'}=12;
$conf{'red_zone_mins'}=8;

# On module instantiation, we'll pull in some environment variables,
# validate them, and copy them to conf vars.
#
# TODO: The validation above

$conf{'env_CHANNEL'}=$ENV{'JOCKEYCALL_CHANNEL'};

# JOCKEYCALL_FLAVOR environment variable should be:
# 0 for production running from /bin
# 1 for production running from /opt/jockeycall
# 2 for development
$conf{'env_FLAVOR'}=$ENV{'JOCKEYCALL_FLAVOR'};

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


sub setdirs
{
# Parameters/info
#
# $_[0]: Numeric day of week (from localtime[6])
#
# Package-level variables used:
#  $conf{'basedir'},$conf{'subdir_wday'},$conf{'schedules_at'},
#  $conf{'vars_at'}

	# Bounce if we get an invalid DOW for some reason.
	return 0
	 if(($_[0]>6)||($_[0]<0));
	
	my $temp=$conf{'subdir_wday'.$_[0]};

	$conf{'SCD'}="$conf{'basedir'}/$conf{'schedules_at'}/$temp";
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


sub check_conf_metadatadir
{
#Debug::trace_out("*** check_conf_metadatadir($_[0])");
# Parameters/info
#
# Verify conf_metadatadir is defined and exists.
# 
# Returns 1 if conf_metadatadir is OK, 0 if it is not
#
# Package-level variables used:
#  $conf{'basedir'}, $conf{'metadatadir'}

	return 0
	 if(($conf{'basedir'} eq '')or($conf{'metadatadir'} eq ''));
	return 0
	 if(! -e "$conf{'basedir'}/$conf{'metadatadir'}");

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

        while(<$jockeycallconf_file_handle>)
        {
                my $line=$_;
		$line=~s/^\s+|\s+$//g;

		next if($line eq ''); # skip blank lines
		next if($line =~ /^\s*#/); # skip lines beginning with # - comments

		# all configuration lines are a token, space, then value.
		# TODO: something to account for comments in the middle of lines
                my($first,$rest)=split(' ',$line,2);

# known configuration items
                if($first eq   'at_exe')
			{$conf{'at_exe'}=$rest; next;}
                if($first eq   'jockeycall_bin_curl')
			{$conf{'jockeycall_bin_curl'}=$rest; next;}
                if($first eq   'jockeycall_bin_mp3info')
			{$conf{'jockeycall_bin_mp3info'}=$rest; next;}
                if($first eq   'jockeycall_bin_ezstream')
			{$conf{'jockeycall_bin_ezstream'}=$rest; next;}
                if($first eq   'jockeycall_banner_service_enabled')
			{$conf{'jockeycall_banner_service_enaled'}=$rest; next;}
                if($first eq   'jockeycall_banner_base_path')
			{$conf{'jockeycall_banner_base_path'}=$rest; next;}
                if($first eq   'jockeycall_banner_service_autoflip_every')
			{$conf{'jockeycall_banner_service_autoflip_every'}=$rest; next;}
                if($first eq   'jockeycall_banner_service_enabled')
			{$conf{'jockeycall_banner_service_enabled'}=$rest; next;}
                if($first eq   'jockeycall_banner_service_url')
			{$conf{'jockeycall_banner_service_url'}=$rest; next;}
                if($first eq   'jockeycall_banner_service_key')
			{$conf{'jockeycall_banner_service_key'}=$rest; next;}
                Debug::conf_error_out "-- unknown jockeycallconf configuration item $first found in file";
        }

        close($jockeycallconf_file_handle);

# Delicious validation for global configuration
# ----------------------------------------------
	my $jockeycallconf_error_flag=0;
	$disable_banners=0;

	if($conf{'jockeycall_bin_curl'} eq '')
	{
		$jockeycall_bin_curl='/bin/curl';
	}
	if($conf{'jockeycall_bin_ezstream'} eq '')
	{
		$jockeycall_bin_ezstream='/usr/bin/ezstream';
	}

# this is NOT working to find ezstream at /usr/local/bin/ezstream
# ??? TODO: Find out why
#	if(! -e $conf{'$jockeycall_bin_ezstream'})
#	{
#		Debug::error_out "ezstream binary \"".$conf{'jockeycall_bin_ezstream'}."\" not found, transmit subcommand won't work";
#		Debug::error_out "fix that by installing ezstream, your distro likely has it";
#	}

	if($conf{'jockeycall_bin_mp3info'} eq '')
	{
                Debug::conf_error_out "jockeycall_bin_mp3info not specified";
		$jockeycallconf_error_flag=1;
	}
	elsif(! -e $conf{'jockeycall_bin_mp3info'})
	{
                Debug::conf_error_out "jockeycall_bin_mp3info \"".$conf{'jockeycall_bin_mp3info'}."\" not found";
		$jockeycallconf_error_flag=1;
	}

	if(! -e $conf{'jockeycall_bin_curl'})
	{
		Debug::error_out "curl binary \"".$conf{'jockeycall_bin_curl'}."\" not found, won't do banner operations";
		Debug::error_out "fix that by installing curl, your distro likely has it";
		$disable_banners=1;		
	}
	if(! -e $conf{'$banner_service_base_path'})
	{
		Debug::error_out "banner base path \"".$conf{'$banner_service_base_path'}."\" not found, won't do banner operations";
		$disable_banners=1;		
	}	
	if($conf{'jockeycall_banner_service_url'} eq '')
	{
		Debug::error_out "banner service url is blank or undefined, won't do banner operations";
		$disable_banners=1;		
	}
	if($conf{'jockeycall_banner_service_key'} eq '')
	{
		Debug::error_out "banner service key is blank or undefined, won't do banner operations";
		$disable_banners=1;		
	}
	if($conf{'jockeycall_banner_service_enabled'}!=1)
	{
		$disable_banners=1;
	}


# report any errors.
#
        if($conf_error_flag==1)
        {
                Debug::conf_error_out "configuration failed validation";
                return 0
        }
        else
        {
                $conf{'valid'}=1;
        }
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
#  A lot because we're setting variables according to a configuration file.
#  $conf{'basedir'}'s pretty critical.

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

	while(<$conf_file_handle>)
	{
		my $line=$_;
		my($first,$rest)=sift_conf_line($line);
		next if($first eq '');
		#$line=~s/^\s+|\s+$//g;
#
#		next if($line eq ''); # skip blank lines
#		next if($line =~ /^\s*#/); # skip lines beginning with # - comments
#
#		# all configuration lines are a token, space, then value.
#		# TODO: something to account for comments in the middle of lines
#		my($first,$rest)=split(' ',$line,2);

# known configuration items
		if($first eq 'subdir_wday_sun')	{$conf{'subdir_wday0'}=$rest; next;}
		if($first eq 'subdir_wday_mon')	{$conf{'subdir_wday1'}=$rest; next;}
		if($first eq 'subdir_wday_tue')	{$conf{'subdir_wday2'}=$rest; next;}
		if($first eq 'subdir_wday_wed')	{$conf{'subdir_wday3'}=$rest; next;}
		if($first eq 'subdir_wday_thu')	{$conf{'subdir_wday4'}=$rest; next;}
		if($first eq 'subdir_wday_fri')	{$conf{'subdir_wday5'}=$rest; next;}
		if($first eq 'subdir_wday_sat')	{$conf{'subdir_wday6'}=$rest; next;}
		if($first eq 'day_flip_at')	{$conf{'day_flip_at'}=$rest; next;}

		if($first eq 'track_td')	{$conf{'track_td'}=$rest; next;}
		if($first eq 'track_um')	{$conf{'track_um'}=$rest; next;}

		if($first eq 'schedules_at')	{$conf{'schedules_at'}=$rest; next;}
		if($first eq 'vars_at')		{$conf{'vars_at'}=$rest; next;}
		if($first eq 'metadatadir')	{$conf{'metadatadir'}=$rest; next;}
		if($first eq 'oob_queue_at')	{$conf{'oob_queue_at'}=$rest; next;}
		if($first eq 'intermission_at')	{$conf{'intermission_at'}=$rest; next;}
		if($first eq 'logs_at')		{$conf{'logs_at'}=$rest; next;}

		if($first eq 'random_percent')	{$conf{'random_percent'}=$rest; next;}

		if($first eq 'yellow_zone_mins'){$conf{'yellow_zone_mins'}=$rest; next;}
		if($first eq 'red_zone_mins')	{$conf{'red_zone_mins'}=$rest; next;}

		Debug::conf_error_out "-- unknown channel configuration item $first found in file";
	}

	close($conf_file_handle);

# Delicious validation for channel configuration
# ----------------------------------------------
	$conf_error_flag=0;

# - conf_basedir
	if($conf{'basedir'} eq '')
	{
		Debug::conf_error_out "channel conf problem: basedir doesn't appear in configuration file or had no value";
		$conf_error_flag=1;
	}
	elsif(! -e $conf{'basedir'})
	{
		Debug::conf_error_out "channel conf problem: basedir \"$conf{'basedir'}\" not found";
		$conf_error_flag=1;
	}
#
# - conf_track_td
	if($conf{'track_td'} eq '')
	{
		Debug::conf_error_out "channel conf problem: track_td doesn't appear in configuration file or had no value";
		$conf_error_flag=1;
	}
	elsif(! -e "$conf{'basedir'}/$conf{'track_td'}")
	{
		Debug::conf_error_out "channel conf problem: track_td file \"$conf{'track_td'}\" inaccessible or doesn't exist";
		$conf_error_flag=1;
	}
#
# - conf_track_um
	if($conf{'track_um'} eq '')
	{
		Debug::conf_error_out "channel conf problem: track_um doesn't appear in configuration file or had no value";
		$conf_error_flag=1;
	}
	elsif(! -e "$conf{'basedir'}/$conf{'track_um'}")
	{
		Debug::conf_error_out "channel conf problem: track_um file \"$conf{'track_um'}\" inaccessible or doesn't exist";
		$conf_error_flag=1;
	}
#
# - conf_vars_at
	if($conf{'vars_at'} eq '')
	{
		Debug::conf_error_out "channel conf problem: vars_at doesn't appear in configuration file or had no value";
		$conf_error_flag=1;
	}
	elsif(! -e "$conf{'basedir'}/$conf{'vars_at'}")
	{
		Debug::conf_error_out "channel conf problem: vars_at dir \"$conf{'basedir'}/$conf{'vars_at'}\" inaccessible or doesn't exist";
		$conf_error_flag=1;
	}
#
# - conf_schedules_at
	if($conf{'schedules_at'} eq '')
	{
		Debug::conf_error_out "channel conf problem: schedules_at doesn't appear in configuration file or had no value";
		$conf_error_flag=1;
	}
	elsif(! -e "$conf{'basedir'}/$conf{'schedules_at'}")
	{
		Debug::conf_error_out "channel conf problem: schedules_at dir \"$conf{'basedir'}/$conf{'schedules_at'}\" inaccessible or doesn't exist";
		$conf_error_flag=1;
	}
#
# - conf_metadatadir
	if($conf{'metadatadir'} eq '')
	{
		Debug::conf_error_out "channel conf problem: metadatadir doesn't appear in configuration file or had no value";
		$conf_error_flag=1;
	}
	elsif(! -e "$conf{'basedir'}/$conf{'metadatadir'}")
	{
		Debug::conf_error_out "channel conf problem: metadatadir \"$conf{'basedir'}/$conf{'metadatadir'}\" inaccessible or doesn't exist";
		$conf_error_flag=1;
	}
#
# - conf_oob_queue_at
	if($conf{'oob_queue_at'} eq '')
	{
		Debug::conf_error_out "channel conf problem: oob_queue_at doesn't appear in configuration file or had no value";
		$conf_error_flag=1;
	}
	elsif(! -e "$conf{'basedir'}/$conf{'oob_queue_at'}")
	{
		Debug::conf_error_out "channel conf problem: oob_queue_at dir \"$conf{'basedir'}/$conf{'oob_queue_at'}\" inaccessible or doesn't exist";
		$conf_error_flag=1;
	}
#
# - conf_intermission_at
	if($conf{'intermission_at'} eq '')
	{
		Debug::conf_error_out "channel conf problem: intermission_at doesn't appear in configuration file or had no value";
		$conf_error_flag=1;
	}
	elsif(! -e "$conf{'basedir'}/$conf{'intermission_at'}")
	{
		Debug::conf_error_out "channel conf problem: intermission_at dir \"$conf{'basedir'}/$conf{'intermission_at'}\" inaccessible or doesn't exist";
		$conf_error_flag=1;
	}
#
# - logs_at
	if($conf{'logs_at'} eq '')
	{
		$conf{'logs_at'}='.';
	}
	elsif(! -e "$conf{'basedir'}/$conf{'logs_at'}")
	{
		Debug::conf_error_out "channel conf problem: logs_at dir \"$conf{'basedir'}/$conf{'logs_at'}\" inaccessible or doesn't exist";
		$conf_error_flag=1;
	}
#
# - random_percent
# TODO: make sure is numeric and a sane value

#
# - yellow_zone_mins
# TODO: make sure is numeric and a sane value

#
# - red_zone_mins
# TODO: make sure is numeric and a sane value


#
# report any errors.
#
        if($conf_error_flag==1)
        {
                Debug::conf_error_out "configuration failed validation";
                return 0
        }
        else
        {
                $conf{'valid'}=1;
        }
	return 1;
}

1;

