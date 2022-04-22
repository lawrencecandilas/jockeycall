package BannerUpdate;
use parent 'Exporter';
use List::Util qw(shuffle);
require 'Debug.pm';
require 'Conf.pm';
require 'DataMoving.pm';

# This module uses curl to interact with an HTTP API to provide a banner and
# channel information on a website.

$GCURLCMD=$Conf::conf{'jockeycall_bin_curl'};

our $Gcurrent_timeslot='zzzzz';
our $Gnext_timeslot='zzzzz';

our $GIntermission=0;
our $GDoUpdate=0;

my $enabled=$Conf::conf{'jockeycall_banner_service_enabled'};
our $GServiceURL=%Conf::conf{'jockeycall_banner_service_url'};
our $GKey=%Conf::conf{'jockeycall_banner_service_key'};

our @GBanners=();
our $GChannel='';
our @GInfoLine;

our $ChanBase;
our $TimeslotBase;

our @GInfolines=();

# Module needs this info to compute time display to give to banner microservice.

sub set_timeslot_info
{
	Debug::trace_out("*** BannerUpdate::set_timeslot_info(\"".$_[0]."\",\"".$_[1]."\")");
	$Gcurrent_timeslot=$_[0];
	$Gnext_timeslot=$_[1];
	return 0;
}

# If in intermission mode, the time display will say "Intermission until
# XX:XX", so module needs to know that.

sub set_intermission_flag
{
	Debug::trace_out("*** BannerUpdate::set_intermission_flag()");
	$GIntermission=1;
}

# now_play(), when called, simply calls updateChannelInfo(0 every time.
# It will return immediately unless the update flag is set.
#
# So if something wants the channel information to be updated, it should call
# set_doUpdate_flag().
#

sub clear_doUpdate_flag
{
	Debug::trace_out("*** BannerUpdate::clear_doUpdate_flag()");
	$GDoUpdate=0;
}
sub set_doUpdate_flag
{
	Debug::trace_out("*** BannerUpdate::set_doUpdate_flag()");
	$GDoUpdate=1;
}

# Paths and channel name needed so module can find banner files.
sub set_channel
{
	Debug::trace_out("*** BannerUpdate::set_channel(\"$_[0]\",\"$_[1]\")");
	$GChannel=$_[0];
	$ChanBase=$_[1];
}
sub set_timeslot
{
	Debug::trace_out("*** BannerUpdate::set_timeslot(\"$_[0]\")");
	$TimeslotBase=$_[0];
}

# A subcommand can be used to callback a flip.
# This allows using the at command to schedule the flip, 1 minute into the
# future.
# This is a cheap way of not making ezstream wait until the flip is completed 
# for the next song.

sub schedule_flip
{
#        Debug::trace_out("*** BannerUpdate::schedule_flip()");
#        if($GDoUpdate!=1)
#        {
#                Debug::trace_out("BannerUpdate::flip(): Exiting because GDoUpdate isn't 1.");
#                return 1;
#        }
#
#	Debug::debug_out("Scheduling a banner flip in 1 minute");
#
#	my $command="echo \"$0 $ChanBase bannerflip ".$TimeslotBase." ".$GIntermission." ".$Gcurrent_timeslot." ".$Gnext_timeslot."\" | at now + 1 minute";
#
#	Debug::debug_out("Command: $command");
#
#	my $result=qx\$command\;
#
#	return $result;
}

# Loads banners from station, channel, and timeslot, and then updates

sub flip
{
# If enabled ...
        if($enabled!=1)
        {
                Debug::trace_out("Banners not enabled in config.  Doing nothing here.");
                return;
        }

	if($ChanBase ne '')
	{
		add2set($ChanBase.'/banners/station-mandatory',100,100);
		add2set($ChanBase.'/banners/station/',75,100);
		add2set($ChanBase.'/banners/mandatory',100,100);
		add2set($ChanBase.'/banners',75,100);
	}
	if($TimeslotBase ne '')
	{
		add2set($TimeslotBase.'/banners/mandatory',100,100);
		add2set($TimeslotBase.'/banners',75,100);
	}
	updateChannelInfo();
}

sub url_encode
{
# https://www.perlmonks.org/?node_id=1179436
	my $rv = shift;
	$rv =~ s/([^a-z\d\Q.-_~ \E])/sprintf("%%%2.2X", ord($1))/geix;
	$rv =~ tr/ /+/;
	return $rv;
}

sub serviceInterface
{
# 
# Send command to banner microservice, and report result.
#
	$in_channel=$_[0];
	$in_op=$_[1];
	$in_p1=$_[2];
	$in_p2=$_[3]; $in_p3=$_[4]; $in_p4=$_[5];

	if($GCURLCMD eq '')
	{
		Debug::error_out("BannerUpdate::serviceInterface(): GCURLCMD global is null");
		return 0;
	}
	if($GServiceURL eq '')
	{
		Debug::error_out("BannerUpdate::serviceInterface(): GServiceURL global is null");
		return 0;
	}
	if($GKey eq '')
	{
		Debug::error_out("BannerUpdate::serviceInterface(): GKey global is null");
		return 0;
	}
	if($in_channel eq '')
	{
		Debug::error_out("BannerUpdate::serviceInterface(): in_channel is null");
		return 0;
	}
	if($in_op eq '')
	{
		Debug::error_out("BannerUpdate::serviceInterface(): in_op is null");
		return 0;
	}

	my $c='';

	if($in_op eq '01')
	{
		$c="-d \"k=$GKey\" \"$GServiceURL?a=$in_op&c=$in_channel\"";
	}

	if($in_op eq '02')
	{
		$c="-d \"k=$GKey\" -d \"1=$_[2]\" -d \"2=$_[3]\" -d \"3=$_[4]\" -d \"4=$_[5]\" \"$GServiceURL?a=$in_op&c=$in_channel\"";
	}

	if($in_op eq '05')
	{
		$c="-d \"k=$GKey\" -d \"5=$_[2]\" \"$GServiceURL?a=$in_op&c=$in_channel\"";
	}

	if($in_op eq '11')
	{
		$c="-d \"k=$GKey\" -d \"1=$_[2]\" -d \"2=$_[3]\" -d \"3=$_[4]\" -d \"4=$_[5]\" \"$GServiceURL?a=$in_op&c=$in_channel\"";
	}

	if($in_op eq '15')
	{
		$c="-d \"k=$GKey\" -d \"5=$_[2]\" \"$GServiceURL?a=$in_op&c=$in_channel\"";
	}

        if($in_op eq '04')
	{
		$c="-d \"k=$GKey\" \"$GServiceURL?a=$in_op&c=$in_channel\"";
        }

	if($in_op eq '03')
	{
		if($in_p1 ne '')
		{
			$c="-F \"k=$GKey\" -F \"banner=\@$in_p1\" \"$GServiceURL?a=03&c=$in_channel\"";
		}
	}

	if($c eq '')
	{
		Debug::debug_out("BannerUpdate::serviceInterface(): unsupported op \"$in_op\"");
		return 0;
	}

	$output=qx/$GCURLCMD --insecure -sS $c/;
	$didItWork=scalar(grep('OK,',$output));
	sleep 1;

	if($didItWork==0)
	{
		Debug::debug_out("== FAILED ==	$in_p1");
		Debug::error_out("== FAILED ==	$in_p1");
	}
	else
	{
		Debug::debug_out("ok		$in_p1");

	}
	return $didItWork;
}

sub updateChannelInfo
{
	Debug::trace_out("*** BannerUpdate::updateChannelInfo()");
# If enabled ...
	if($enabled!=1)
	{
		Debug::trace_out("Banners not enabled in config.  Doing nothing here.");
		return;
	}
# A frontend for actuallyUpdateChannelInfo(), this is done so we can time the
# operation and write it to the bflip log.
#
	Debug::bflip_log_open();
	Debug::bflip_out($main::timestamp_hms.': Begin transaction.');
	my $t=time;
	my $result=actuallyUpdateChannelInfo();
	my $t=time-$t;
	if(substr($result,0,1) eq 'S')
	{
		Debug::bflip_out($main::timestamp_hms.': End transaction ('.$t.'s) - success - '.$result);
	}
	else
	{
		Debug::bflip_out($main::timestamp_hms.': End transaction ('.$t.'s) - failure - '.$result);
	}
}

sub actuallyUpdateChannelInfo
{
	Debug::trace_out("*** BannerUpdate::actuallyUpdateChannelInfo()");
# If enabled ...
	if($enabled!=1){
		Debug::trace_out("Banners not enabled in config.  Doing nothing here.");
		return 'Banners not enabled';
	}
# Conduct the transaction that updates banners and channel information in the
# microservice.
# Microservice is then used by a web front end to display banners and channel
# information.
#
	if($GChannel eq '')
	{
		Debug::error_out("BannerUpdate::actuallyUpdateChannelInfo(): GChannel is null.");
		return;
	}

	Debug::trace_out("begin service calls ...");
	Debug::trace_out("New		");

	my $result=serviceInterface($GChannel,'01',$GChannel);
	return 'Failed at 01 New' if($result!=1);

# Assemble infolines
	
# descriptionShort
	$GInfoline[0]=DataMoving::read_file_string($GChannel.'/info/descriptionShort.txt');
	if(!defined($GInfoline[0]))
	{
		$GInfoline[0]='<p>'.main::basename($GChannel).' on GROWL</p>';
	}

# descriptionLong
	$GInfoline[1]=DataMoving::read_file_string($GChannel.'/info/descriptionLong.txt');
	if(!defined($GInfoline[1]))
	{
		$GInfoline[1]='<p>You are listening to '.main::basename($GChannel).' on GROWL</p>';
	}

# currentShow
	$GInfoline[2]=DataMoving::read_file_string($GChanBase.'/info/currentShow.txt');
	if(!defined($GInfoline[2]))
	{
		if($GIntermission!=0)
		{
			$GInfoline[2]='<p>Thanks for tuning in.  We are currently in intermission.</p>'
		}
		else
		{		
			$GInfoline[2]='<p>Thanks for tuning in.  We hope you enjoy the show!</p>'
		}
	}

# currentShowTime
	if(($Gcurrent_timeslot=='zzzzz') or ($Gnext_timeslot=='zzzzz') or ($Gcurrent_timeslot==$Gnext_timeslot))
	{

		if($GIntermission!=0)
		{
			$GInfoline[3]='<p>This channel is undergoing maintenance, please check back later.</p>';
		}
		else
		{
			$GInfoline[3]='<p>Check back later for schedule and programming updates!</p>';
		}
	}
	else
	{
		if($GIntermission!=0)
		{
			$GInfoline[3]='<p>Our next program starts at '.Utility::datestring_to_human_readable_time($Gnext_timeslot).'</p>';
		}
		else
		{
			$GInfoline[3]='<p>'.Utility::datestring_to_human_readable_time($Gcurrent_timeslot).'-'.Utility::datestring_to_human_readable_time($Gnext_timeslot).'</p>';
		}
	}	

	Debug::trace_out("Infolines	");

	$result=serviceInterface($GChannel,'02',$GInfoline[0],$GInfoline[1],$GInfoline[2],$GInfoline[3]);
	return 'Failed at 02 Infolines' if($result!=1);

	my $n=0;
	foreach my $b(@GBanners)
	{
		$n++;

		Debug::trace_out("Send	".$n."/".scalar(@GBanners)."	");

		my $result=serviceInterface($GChannel,'03',$b);
		return 'Failed at 03 Send ('.$n.'/'.scalar(@GBanners).' sent successfully)' if($result!=1);
	}

	Debug::trace_out("Schedule	");
	
	$result=serviceInterface($GChannel,'05',HTMLSchedule::html_schedule($GChannel));
	return 'Failed at 05 Schedule' if($result!=1);

	Debug::trace_out("Commit		");

	$result=serviceInterface($GChannel,'04','');
	return 'Failed at 04 Commit' if($result!=1);

	return 'Success ('.scalar(@GBanners).' sent successfully)';
}

sub add2set{
	$in_dir=$_[0];
	$in_lowpercent=$_[1];
	$in_highpercent=$_[2];

	if($in_dir eq '')
	{
		Debug::error_out("BannerUpdate::add2set(): in_dir is null.\n");
		return;
	}
	if(! -d $in_dir)
	{
		return 0;
	}

	Debug::debug_out("BannerUpdate::add2set(): adding set $in_dir\n");
	
	my $p=$in_lowpercent+int(rand(($in_highpercent+1)-$in_lowpercent));
	my @d=();
	opendir(DIR,$in_dir);

	while(my $f=readdir(DIR))
	{
		next if($f =~ m/^\./);
		if(-d "$in_dir/$f"){next;};
		push(@d,"$in_dir/$f");
	}

	my @d2=shuffle @d;
	my $n=int(($p*scalar(@d2))/100);
	return if($n==0);

	for(my $i=0;$i<=($n-1);$i++)
	{
		push(@GBanners,$d2[$i]);			
	}
}

1;
