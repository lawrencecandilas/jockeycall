package Concurrency;
require 'Debug.pm';
use parent 'Exporter';

# Locking and ending

# Either succeed() or fail() should be used to end the instance in all cases.

sub release_lock; # predeclared because we use it in succeed() below

sub succeed
{
Debug::trace_out "*** succeed($_[0])";
# Parameters/info
#
# Reports success and then exits program with error code 0.
# Typically you want a function in TrackDelivery to call this.
# Does not return.
#
# $_[0]: Optional succeed debug message.
#

	release_lock;

	# Optional succeed debug message.
	if($_[0] ne ''){Debug::debug_out $_[0];}
	
	Debug::debug_out 'reporting success and exiting.';
	
	Debug::debug_message_management(2);

	exit 0;
}

sub fail
{
Debug::trace_out "*** fail($_[0])";
# Parameters/info
#
# Reports failure and then exits program with error code 1.
# Typically you want a function in DeliverTrack to call this.
# Does not return.
#
# $_[0]: Optional failure error message.
# $_[1]: Set to 1 to not call technical_difficulties() 
#        Set to 2 to not call technical_difficulties() and output
#        $_[0] to stdout - used for command-line commands.
#
	
	release_lock;
	
	# Optional failure error message.
	if($_[0] ne ''){Debug::error_out($_[0]);}
	
	# If we're trying to play a track and have failed. below is usual.
	##if($_[1]==0){TrackDelivery::technical_difficulties();}

	# If we were processing a command-line command, below is usual.
	if($_[1]==2){print "$_[0]\n";}
	
	Debug::debug_out 'reporting failure and exiting.';
	
	Debug::debug_message_management(2);
	
	exit 1;
}

our $concurrency_lock_code; # Set externally
our $concurrency_lock_flag_acquired;

sub acquire_lock
{
	Debug::trace_out "*** acquire_lock()";
	fail('Conf::check_conf_basedir() failed')if(Conf::check_conf_basedir!=1);

	# Report error if we try to acquire a lock while already acquired.
	return 0 if($concurrency_lock_flag_acquired==1);

# Parameters/info
#
# A lockfile mechanism is used to prevent two concurrent instances of
# this program from stepping on each other.
#
# $concurrency_lock_code needs to be set to a random number before calling.
# OK to call if already locked.
#
# Returns 0 if successful, 1 if that can't be done.
#
# External variables used:
#  $Conf::conf{'basedir'}, $concurrency_lock_code, $concurrency_lock_flag_acquired

# $concurrency_lock_code must be defined before calling.
# This is just a random number.
# Done to try to avoid a race condition of one instance creating a lockfile and a second concurrent instance coming right up behind it and thinking it's the lockfile it made.

	if($concurrency_lock_code eq '')
	{
		Debug::error_out('[Concurrency::acquire_lock] concurrency_lock_code not defined');
		return 0;
	}
	Debug::debug_out "[Concurrency::acquire_lock] I am told the lock code is \"$concurrency_lock_code\"";

	my $lockfile="$Conf::conf{'basedir'}/lockfile";

# We might not be able to make lock file the first time.
	$tries=7;

	while(42)
	{

	$tries=$tries-1;
# give up if out of tries.
	if($tries==0)
	{
		Debug::debug_out("[Concurrency::acquire_lock] existing lock never disappeared");
	return 0;
	}

# if lockfile does not exist ...
	if(! -e $lockfile)
	{
# create it ...
		open my $f,'>',$lockfile 
		or do{
			Debug::debug_out("[Concurrency::acquire_lock] could not create lockfile \"$lockfile\": $!");
			return 0;
		};
# put our lock code in it ...
		print $f $concurrency_lock_code;
		if(!$!)
		{
			Debug::debug_out("[Concurrency::acquire_lock] could not write to lockfile \"$lockfile\": $!");
			close $f
			or do{Debug::debug_out ('[Concurrency::acquire_lock] could not close it either')};
			return 0;
		}
# close it ...
		close $f
		or do{
			 Debug::debug_out("[Concurrency::acquire_lock] could not close lockfile \"$lockfile\" after writing: $!");
			return 0;
		};
# reopen it ...
		open my $f2,'<',$lockfile
		or do{
			Debug::debug_out("[Concurrency::acquire_lock] could not open \"$lockfile\" for readback: $!");
			return 0;
		};
# read it back and verify it's the same one.
		my $lockfile_readback=<$f2>
		or do{
			Debug::debug_out("[Concurrency::acquire_lock] errno $! while reading back from \"$lockfile\": $!");
			close $f2
			or do{Debug::debug_out('[Concurrency::acquire_lock] could not close it either')};
			return 0;
		};
#chomp $lockfile_readback;
		Debug::debug_out "[Concurrency::acquire_lock] lockfile_readback is \"$lockfile_readback\"";
		if($lockfile_readback ne $concurrency_lock_code)
		{
			Debug::error_out "[Concurrency::acquire_lock] lockfile readback did not match lock code \"$concurrency_lock_code\"";
			return 0;
		}
		close $f2
		or do{
			Debug::debug_out("[Concurrency::acquire_lock] could not close lockfile \"$lockfile\" after readback: $!");
			return 0;
		};
		Debug::debug_out('[Concurrency::acquire_lock] match, lock is acquired');
		$concurrency_lock_flag_acquired=1;
		return 1;
	}

# lock file exists if we get here.
# wait a tiny bit and try again.
	Debug::debug_out('[Concurrency::acquire_lock] lockfile exists, trying again in 0.25 second(s)');
	sleep .25;

	}

	return 1;
}

sub release_lock{
	Debug::trace_out "*** release_lock()";
	return 1 if(($concurrency_lock_flag_acquired==0)and($_[0]!=1));

# Parameters/info
#
# Must be called before exiting.  succeed() and fail() normally do
# this.
# OK to call if not acquired.
#
# $_[0]: Set to 1 to ignore internal "lock acquired" flag and try to
#        remove the lock anyway.
#        Used by lockbreak subcommand.
#
# External variables used:
#  $Conf::conf{'basedir'}
#
# Causes infinite loop if something goes wrong and called from fail().
# Don't do that.

	my $lockfile="$Conf::conf{'basedir'}/lockfile";

	if(! -e $lockfile)
	{
		Debug::trace_out("    lockfile \"$lockfile\" didn't exist anyway");
		return 1;
	}

	unlink($lockfile)
	or do{
		Debug::error_out("[Concurrency::release_lock] could not delete lockfile: $!");
		return 0;
	};

	return 1;
}

1;

