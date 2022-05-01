package Debug;
use POSIX qw(strftime);
use parent 'Exporter';

# Debug, trace, and error messaging and logging

our @EXPORT=qw(
	timestamp
        debug_out
        error_out
        trace_out
        debug_message_management
        );

# Timestamps
our $timestamp_localtime;
our $timestamp;
our $timestamp_hms;

# Base directory for log files
# This is set by the first call to debug_message_management()
our $debug_log_basedir='.';

# Debug log file, defined by first call to debug_message_management()
our $debug_log_file;

# 1 appends to debug log file, 0 writes a new one each call.
our $debug_option_append=1;

# Types of messages to include in debug log
# (error log is separate)
# (bflip log is also separate)
our $debug_option_logdebug=1;
our $debug_option_logtrace=1;
our $debug_option_log_filter_trivial=1;
our $debug_option_logerror=1;
our $debug_option_logbflip=1;

# Flag to enable copying what's logged above to stdout.
our $debug_option_stdout=0;

# Again, errors get appended here no matter what, unless null.
# Within $debug_log_basedir
our $debug_error_file='errorfile.txt';

# Interactions with banner service recorded in bflip log.
our $bflip_log_file='bflipfile.txt';

# Internal use
our $debug_fh; 			# File handle of debug log
our $debug_fhe; 		# File handle of error log
our $debug_fhb;			# File handle of bflip log
our $debug_enabled; 		# Internal flag

sub trace_out;

sub stdout_all_the_things
{
	$debug_option_logdebug=1;
	$debug_option_logtrace=1;
	$debug_option_logerror=1;
	$debug_option_logbflip=1;
	$debug_option_stdout=1;
}


sub debug_out
{
	my $t=$_[0]; chomp $t;
	return if(($debug_option_log_filter_trivial==1)and(index($t,'[trivial]')!=-1));

	if(($debug_option_logdebug==1))
	{
		print '[DEBUG] ['.$timestamp_hms.'] '.$t."\n" if($debug_option_stdout==1);
		return if(($_[0] eq '')or($debug_enabled!=1));
		if($debug_fh){print $debug_fh '[DEBUG] ['.$timestamp_hms.'] '.$t."\n";}
	}
}


sub conf_error_out
{
	print '[Configuration Error] '.$_[0]."\n";
}


sub trace_out
{
        my $t=$_[0]; chomp $t;
	return if(($debug_option_log_filter_trivial==1)&&(index($t,'[trivial]')!=-1));

        if($debug_option_logtrace==1)
        {
                print '[TRACE] ['.$timestamp_hms.'] '.$t."\n" if($debug_option_stdout==1);
                return if(($_[0] eq '')or($debug_enabled!=1));
                if($debug_fh){print $debug_fh '[DEBUG] ['.$timestamp_hms.'] '.$t."\n";}
        }
}


sub error_out
{
	my $t=$_[0]; chomp $t;

	if($debug_option_logerror==1)
	{
		print '[ERROR] ['.$timestamp_hms.'] '.$t."\n" if($debug_option_stdout==1);
		if(($_[0] eq '')or($debug_enabled!=1))
		{
			if($debug_fh){print $debug_fh '[ERROR] ['.$timestamp_hms.'] '.$t."\n";}
		}
	}
	if($debug_error_file ne '')
	{
		if($debug_fhe){print $debug_fhe '[ERROR] ['.$timestamp_hms.'] '.$t."\n";}
	}

#	# also write errors to trace log if enabled
#	trace_out('[ERROR] '.$t);
}


sub bflip_log_open
{
	if(open($debug_fhb,'>>',$debug_log_basedir.'/'.$bflip_log_file))
	{
		trace_out "bflip_log_open(): bflip log opened";
	}
	else
	{
		print STDERR "bflip_log_open(): unable to open $debug_log_basedir/$debug_log_file for writing\n";
		$debug_option_logbflip=0;
	}
}


sub bflip_out
{
	my $t=$_[0]; chomp $t;

	if(($debug_option_logbflip==1))
	{
		print '[BFLIP] ['.$timestamp_hms.'] '.$t."\n" if($debug_option_stdout==1);
		return if($_[0] eq '');
		print $debug_fhb '[BFLIP] ['.$timestamp_hms.'] '.$t."\n";
	}
}


sub set_debug_timestamp
{
# Set timestamp variables
# These are included in log files and filenames to identify the session.
#
# This is a separate function so that external code can tell Debug to set the
# timestamp, but not call debug_message_management() if needed.
#
# An example is when external code might want to just dump all debug, error,
# and trace messages to stdout instead of logging to files.  The
# chaninfo_update.pl utility does this.
#
	@timestamp_localtime=localtime;
	$timestamp=strftime '%Y%m%d',@timestamp_localtime;
	$timestamp_hms=$timestamp.'-'.strftime '%H%M%S',@timestamp_localtime;
}


sub debug_message_management
{
	#trace_out "*** debug_message_management($_[0])";
	return if($_[0]==0);

# Parameters/info
#
# $_[0]: 1 to enable and setup, 2 to close down, 0 is ignored
# $_[1]: log directory (for 1 only)
# $_[2]: channel name (for 1 only)
#
# Mostly here so we can open a file to write messages to once, and close when completed.
#
# Module-level variables used:
#  $debug_fh, $debug_fhe, $debug_option_append; $debug_log_file, $debug_enabled

	my $option;
	if($debug_option_append==1){$option='>>'}else{$option='>'};

	if($_[0]==1)
	{
		set_debug_timestamp;
		$debug_log_basedir=$_[1];
		$debug_log_file='debuglog-'.$_[2].'.txt';
		$debug_error_file='errorlog-'.$_[2].'.txt';

# debug_log_file receives all enabled messages, if nothing is enabled this file won't be written to
		if(open($debug_fh,$option,$debug_log_basedir.'/'.$debug_log_file))
		{
			$debug_enabled=1;
			trace_out('    [trivial] [Debug::debug_message_management] 1 - enable and setup - completed');
		}
		else
		{
			print STDERR "[Debug::debug_message_management] unable to open $debug_log_basedir/$debug_log_file for writing\n";
			$debug_log_file='';
			$debug_option_logdebug=0;
			$debug_option_logtrace=0;
		}

# debug_error_file always receives errors regardless of what is enabled
		if(!open($debug_fhe,'>>',$debug_log_basedir.'/'.$debug_error_file))
		{
   			print STDERR "[Debug::debug_message_management] unable to open $debug_log_basedir/$debug_error_file for writing\n";
   			print STDERR "cannot log errors to debug_error_file\n";
			$debug_error_file='';
			$debug_option_logerror=0;
		}
	}

	if(($_[0]==2)and($debug_enabled==1))
	{
		trace_out('    [trivial] [Debug::debug_message_management] 2 - close down');
		close($debug_fh) if($debug_log_file ne '');
		if($debug_error_file ne ''){close($debug_fhe);}
		if($debug_bflip_file ne ''){close($debug_fhb);}
	}

}


1;

