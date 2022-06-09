package Subcommands;
use File::Basename;
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
	Debug::trace_out "*** Subcommand::must_be_something(\"$_[0]\")";

# Small subroutine to ensure parameter exists.
# Won't return if there is an issue, calls fail with option 2.

	if($_[0] eq ''){Concurrency::fail("missing a word",2);}
}

sub must_be_one_of
{
	Debug::trace_out "*** Subcommand::must_be_one_of(\"$_[0]\")";

# Small subroutine to ensure parameter is one of a few desired strings.
# Won't return if there is an issue, calls fail with option 2.

	my $t=shift @_;
	foreach(@_){if($_ eq $t){return;}}
	Concurrency::fail("unrecognized word \"".$t."\"",2);
}

sub command_init
{
	Debug::trace_out "*** Subcommand::command_init()";

	# next call will do banner flip
	DataMoving::set_rkey('need-a-flip',1);

	# push out updated schedule
	$in_channel=$_[0];
	BannerUpdate::serviceInterface($in_channel,15,HTMLSchedule::html_schedule($in_channel));

	Concurrency::succeed;
}

sub command_hsd
{
	Debug::trace_out "*** Subcommand::command_hsd()";
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
	Debug::trace_out "*** Subcommand::command_emp(\"$_[0]\")";

# emp stands for Ezstream Metadata Provider.
#
# With a wrapper script, this will support ezstream's feature which
# queries an external program for metadata.  This function depends
# heavily on the "now-playing" key being set correctly.
#
# This appears to be needed to avoid the artist/title being garbled.

	my $temp=DataMoving::get_rkey('now-playing');

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
	Debug::trace_out "*** Subcommand::command_bannerflip() ***";

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

sub command_test
{
	Debug::trace_out("*** Subcommand::command_test(\"$_[0]\",\"$_[1]\",\"$_[2]\") ***");
	$in_channel=$_[0];
	$in_start_datestring=$_[1];
	$in_end_datestring=$_[2];

	Concurrency::release_lock(1);

	my $track_name;
	my $track_playtime_seconds;
	my $d=$in_start_datestring;
	my $days=0;
	my $days_limit=1;
	my $s=0;

	while(42)
	{
		my $output=`JOCKEYCALL_SIMULATION_MODE=1 JOCKEYCALL_DAY_OFFSET=$days JOCKEYCALL_TIMESLOT=$d ./jockeycall-ezstream-intake-call.pl`;
		$track_name=(split(/\;/,$output))[0];
		chomp $track_name;
		$track_playtime_seconds=(split(/\;/,$output))[1];
		
		print $d.": $track_name\n";

		$d1=Utility::datestring_to_minutes($d);
		$d1=$d1+int(($track_playtime_seconds)/60);
		$s=$s+$track_playtime_seconds-(60*(int($track_playtime_seconds)/60));
		if($s>60){$s=$s-60;$d1++;}
		if($d1>1439)
		{
			$d1=$d1-1440;
			$days++;
		}
		$d=Utility::minutes_to_datestring($d1);

		last if(($d>=$in_end_datestring)and($days==$days_limit));
	}
	Concurrency::succeed;
}

sub command_transmit
{
	Debug::trace_out("*** Subcommand::command_transmit(\"$_[0]\") ***");
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

	# This adds the directory that jockeycall.pl is running from to the 
	# PATH for subsequent processes, such as the one we're about to spawn
	# with `system` below.

	# This enables us to not have to specify the full path to the executable in
	# the ezstream XML file, if $Conf::conf{'deliver-type'} is 'ezstream'.
	$ENV{'PATH'}=$Conf::conf{'mypath'}.':'.$ENV{'PATH'};

	if($Conf::conf{'deliver_type'} eq 'ezstream')
	{
		my $ezstream_xml_file="$Conf::conf{'basedir'}/ezstream/channel-ezstream.xml";
		if(! -e $ezstream_xml_file)
		{
			Concurrency::fail("ezstream XML file not found, I looked here: \"".$ezstream_xml_file."\"");
		}	
	}

	print "$ENV{'JOCKEYCALL_CHANNEL'} transmission start.\n";
	
	if($Conf::conf{'deliver_type'} eq 'ezstream')
	{
		# The environment variable JOCKEYCALL_CHANNEL should have been
		# previously set by main.  ezstream picks up the `channel to
		# play through that.
		#
		
		# Now launch ezstream.
		# This will keep going until there is an error, someone stops
		# it, or the power goes out.
		system "$Conf::conf{'jockeycall_bin_ezstream'}",'-c',"$ezstream_xml_file";

		if($?==0)
		{
			# if ezstream exits without error, we'll do the same.
			Concurrency::succeed;
		}else{
			# otherwise let the user know ezstream died.
			print "$ENV{'JOCKEYCALL_CHANNEL'} transmission interrupted because ezstream exited.\n";
			Concurrency::fail;
		}
	}

	if($Conf::conf{'deliver_type'} eq 'command')
	{
		# The environment variable JOCKEYCALL_CHANNEL should have been
		# previously set by main.
		#
		while(1)
		{
			# Launch ourself and ask ourself to play the next
			# track.
			# Since deliver_type is command, that command will be
			# executed and hopefully things are configured
			# correctly.
			system "$0 next";
			# Don't stop until an error is reported.
			last if($?!=0);
		}

		print "$ENV{'JOCKEYCALL_CHANNEL'} transmission interrupted - an error occrred during the last call.\n";
		Concurrency::fail;
	}

	Concurrency::fail("deliver_type \"$Conf::conf{'deliver_type'}\" not supported");
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
	Debug::trace_out("*** Subcommand::process_subcommand_other_than_next(\"$_[0]\",\"$_[1]\")");
	my $in_channel=$_[0];
	my $in_command=$_[1];

	if($in_command eq 'next')
	{
		Debug::trace_out('subcommand is next - bouncing back'); 
		return 1;
	}
	
	my $in_parameter=$_[2];
	my $in_parameter2=$_[3];
	my $in_parameter3=$_[4];
	Debug::trace_out("    Parameters: \"$_[2]\",\"$_[3]\",\"$_[4]\"");

	if($in_command eq 'oob')
	{
		must_be_something($in_parameter);
		must_be_one_of($in_parameter,'dump','push','delete','delete_all');
		if($in_parameter eq 'push'){must_be_something($in_parameter2);}
		if($in_parameter eq 'delete'){must_be_something($in_parameter2);}
		command_oob($in_channel,$in_parameter,$in_parameter2);
		Concurrency::fail('Subcommand::command_oob() returned unexpectedly',2);
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
		if(Concurrency::release_lock(1))
		{
			Concurrency::succeed;
		}
		else
		{
			Concurrency::fail('Concurrency::release_lock() failed',2);
		}
	}

	if($in_command eq 'ezstream-metadata-provider')
	{
		must_be_one_of($in_parameter,'album','artist','title','nothing','');
		command_emp($in_parameter);
		Concurrency::fail('Subcommand::command_emp() returned unexpectedly',2);
	}

	if($in_command eq 'html-schedule-dump')
	{
		command_hsd($in_channel);
		Concurrency::fail('Subcommand::command_hsd() returned unexpectedly',2);
	}

	if($in_command eq 'init')
	{
		command_init($in_channel);
		Concurrency::fail('Subcommand::command_init() returned unexpectedly',2);
	}

	if($in_command eq 'transmit')
	{
		command_transmit($in_channel);
		Concurrency::succeed;	
	}

	if($in_command eq 'test')
	{
		if($in_parameter eq ''){$in_parameter=$Conf::conf{'day_flip_at'};}
		if($in_parameter2 eq ''){$in_parameter2='12359';}
		command_test($in_channel,$in_parameter,$in_parameter2);
		Concurrency::succeed;
	}

	Concurrency::fail("Unknown command $in_command",2);
}

1;
