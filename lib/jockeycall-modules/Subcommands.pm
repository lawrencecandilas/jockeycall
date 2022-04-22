package Subcommands;
use parent 'Exporter';
require 'Debug.pm';
require 'Conf.pm';
require 'Concurrency.pm';
require 'DataMoving.pm';
require 'HTMLSchedule.pm';

# Handle subcommands other than next
# Code here will do things other than find a next track to play

our @EXPORT=qw(
	process_subcommand_other_than_next
        );

sub must_be_something
{
	Debug::trace_out "*** must_be_something(\"$_[0]\")";

# Small subroutine to ensure parameter exists.
# Won't return if there is an issue, calls fail with option 2.

	if($_[0] eq ''){Concurrency::fail("missing a word",2);}
}

sub must_be_one_of
{
	Debug::trace_out "*** must_be_one_of(\"$_[0]\")";

# Small subroutine to ensure parameter is one of a few desired strings.
# Won't return if there is an issue, calls fail with option 2.

	my $t=shift @_;
	foreach(@_){if($_ eq $t){return;}}
	Concurrency::fail("unrecognized word \"".$t."\"",2);
}

sub command_init
{
	Debug::trace_out "*** command_init()";

	# next call will do banner flip
	DataMoving::set_rkey('need-a-flip',1);

	# push out updated schedule
	$in_channel=$_[0];
	BannerUpdate::serviceInterface($in_channel,15,HTMLSchedule::html_schedule($in_channel));

	Concurrency::succeed;
}

sub command_hsd
{
	Debug::trace_out "*** command_hsd()";
#
# hsd stands for HTML Schedule Dump
# 
# This will output an HTML version of the schedule

	$in_channel=$_[0];
	my $o=HTMLSchedule::html_schedule($in_channel);
	print $o."\n";
	exit 0;
}

sub command_emp
{
	Debug::trace_out "*** command_emp(\"$_[0]\")";

# emp stands for Ezstream Metadata Provider.
#
# With a wrapper script, this will support ezstream's feature which
# queries an external program for metadata.  This function depends
# heavily on the "now-playing" key being set correctly.
#
# This appears to be needed to avoid the artist/title being garbled.

	my $temp=DataMoving::get_rkey("now-playing");

	if($_[0] eq 'artist')
	{
		my @temp2=split(/-/,$temp);
		$temp2[0]=~s/^\s+|\s+$//g;
		print $temp2[0]."\n";
		Concurrency::succeed;
	}

	if($_[0] eq 'album')
	{
		print "\n";
		Concurrency::succeed;
	}

	if($_[0] eq 'title')
	{
		my @temp2=split(/-/,$temp);
		$temp2[1]=~s/^\s+|\s+$//g;
		print $temp2[1]."\n";
		Concurrency::succeed;
	}

	if(($_[0] eq 'nothing')||($_[0] eq ''))
	{
		print "$temp\n";
		Concurrency::succeed;
	}

	Concurrency::succeed;
}

sub command_bannerflip
{
	Debug::trace_out "*** command_bannerflip() ***";

	# Note:
	# BannerUpdate::set_channel() is done already by main

	BannerUpdate::set_timeslot($_[1]);

	BannerUpdate::set_doUpdate_flag();

	if($_[2]==1)
	{
		BannerUpdate::set_intermission_flag();
	}

	BannerUpdate::set_timeslot_info($_[3],$_[4]);

	BannerUpdate::flip();
	Concurrency::succeed;
}

sub command_transmit
{
	Debug::trace_out "*** command_transmit() ***";
	$in_channel=$_[0];

	# Hapless user probably wants to see errors on the terminal.
	$Debug::debug_option_stdout=1;
	Debug::set_debug_timestamp;

	Concurrency::release_lock(1);

	# The below won't work because Conf::setdirs is not called by main 
	# when the flow gets here to process the transmit subcommand.  Not
	# sure how or if worth resolving at the moment.

        ## next call will do banner flip
        ##DataMoving::set_rkey('need-a-flip',1);
	##
        ## push out updated schedule
        ##BannerUpdate::serviceInterface($in_channel,15,HTMLSchedule::html_schedule($in_channel));

	# Transmission loop
	# This was a bash script.

	#if(! -e "$Conf::Conf{'jockeycall_bin_ezstream'}")
	#	{
	#	Concurrency::fail("can't find ezstream at \"".$Conf::conf{'jockeycall_bin_ezstream'}."\", so install it if you want to do this.");
	#	}
		
	my $ezstream_xml_file="$Conf::conf{'basedir'}/ezstream/channel-ezstream.xml";
	if(! -e $ezstream_xml_file)
	{
		Concurrency::fail("ezstream XML file not found, I looked here: \"".$ezstream_xml_file."\"");
	}	

	my $firstplay=0;
	while(1)
	{
		# The environment variable JOCKEYCALL_CHANNEL should have been
		# previously set by main.
		#
		print "$ENV{'JOCKEYCALL_CHANNEL'} transmission start.\n";
		print "$Conf::conf{'jockeycall_bin_ezstream'} -c '$ezstream_xml_file'\n";
		system "$Conf::conf{'jockeycall_bin_ezstream'}",'-c',"$ezstream_xml_file";

		# if ezstream exits without error, we'll do the same.
		if($?==0)
		{
			Concurrency::succeed;
		}

		print "$ENV{'JOCKEYCALL_CHANNEL'} transmission interrupted because ezstream exited.\n";

		# if ezstream exits with error, we won't retry if it's the
		# first call.
		if($ezstream_errors==0)
		{
			Concurrency::fail('ezstream failed on first call, assuming config or setup error.');
		}

		print "$ENV{'JOCKEYCALL_CHANNEL'} will start again...\n";
		sleep 1;
		Concurrency::release_lock(1);
		$ezstream_errors=$ezstream_errors+1;

	}
}

sub command_oob
{
	use OOB;
	OOB::set_channel($_[0]);

	if(!Concurrency::acquire_lock)
	{
		print "unable to acquire lock\n";
		Concurrency::fail('[Subcommand::command_oob] unable to acquire lock');
	}

	if($_[1] eq 'dump')
	{
		if(!DataMoving::oob_queue_dump)
		{
			print "DataMoving::oob_queue_dump failed\n";
			Concurrency::fail('[Subcommand::command_oob] DataMoving::oob_queue_dump failed');
		}
	}

	if($_[1] eq 'push')
	{
		if(!OOB::oob_push($_[2]))
		{
			print "OOB::oob_push failed\n";
			Concurrency::fail('[Subcommand::command_oob] OOB::oob_push failed');
		}
	}

	if($_[1] eq 'delete')
	{
		print "not implemented yet\n";
	}

	if($_[1] eq 'delete_all')
	{
		print "not implemented yet\n";
	}

	Concurrency::succeed;
}

sub process_subcommand_other_than_next
{
	my $in_channel=$_[0];
	my $in_command=$_[1];
	if($in_command eq 'next')
	{
		return 1;
	}
	
	my $in_parameter=$_[2];
	my $in_parameter2=$_[3];
	my $in_parameter3=$_[4];

	if($in_command eq 'oob')
	{
		must_be_something($in_parameter);
		must_be_one_of($in_parameter,'dump','push','delete','delete_all');
		if($in_parameter eq 'push'){must_be_something($in_parameter2);}
		if($in_parameter eq 'delete'){must_be_something($in_parameter2);}
		command_oob($in_channel,$in_parameter,$in_parameter2);
		Concurrency::fail("command_oob() returned unexpectedly",2);
	}
	
	if($in_command eq 'bannerflip')
	{
		my $in_TimeslotBase=$in_parameter;
		my $in_intermission_flag=$ARGV[3];
		my $in_current_timeslot=$ARGV[4];
		my $in_next_timeslot=$ARGV[5];
		must_be_something($in_TimeslotBase);
		must_be_something($in_intermission_flag);
		must_be_something($in_current_timeslot);
		must_be_something($in_next_timeslot);
		command_bannerflip(
			 $in_channel
			,$in_TimeslotBase
			,$in_intermission_flag
			,$in_current_timeslot
			,$in_next_timeslot
			)		
	}

	if($in_command eq 'clearlock')
	{
		Debug::trace_out $in_command;
		if(Concurrency::release_lock(1))
		{
			Concurrency::succeed;
		}
		else
		{
			Concurrency::fail('release_lock() failed',2);
		}
	}

	if($in_command eq 'test')
	{
		if(!Utility::check_datestring($ARGV[2]))
		{
			Concurrency::fail('bad datestring',2);
		}
		$main::TESTMODE=1;
		$main::TESTMODE_datestring=$ARGV[2];
		Concurrency::release_lock(1);
		return 0;
	}

	if($in_command eq 'ezstream-metadata-provider')
	{
		Debug::trace_out $in_command;
		must_be_one_of($in_parameter,'album','artist','title','nothing','');
		command_emp($in_parameter);
		Concurrency::fail("command_emp() returned unexpectedly",2);
	}

	if($in_command eq 'html-schedule-dump')
	{
		Debug::trace_out $in_command;
		command_hsd($in_channel);
		Concurrency::fail("command_hsd() returned unexpectedly",2);
	}

	if($in_command eq 'init')
	{
		Debug::trace_out $in_command;
		command_init($in_channel);
		Concurrency::fail("command_init() returned unexpectedly",2);
	}

	if($in_command eq 'transmit')
	{
		Debug::trace_out $in_command;
		command_transmit($in_channel);
		Concurrency::succeed;	
	}

	Concurrency::fail("Unknown command $in_command",2);
}

1;
