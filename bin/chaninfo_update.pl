#!/usr/bin/perl
use File::Basename;
use List::Util qw(shuffle);

use lib '../lib/jockeycall-modules';
use Utility;
use Debug;
$Debug::debug_option_stdout=1;
Debug::set_debug_timestamp;
use Conf;

# Globals

@GBanners=();
$GChannel='';

# Main

my $command=$ARGV[0];

if($command eq ''){

	print "Command not specified.\n";
	exit 0;

}

#Debug::debug_message_management(1,$Conf::conf{'basedir'}.'/'.$Conf::conf{'logs_at'},$channel);

Conf::read_jockeycallconf(basename($0));
$GCURLCMD=	$Conf::conf{'jockeycall_bin_curl'};
$GServiceURL=	$Conf::conf{'jockeycall_banner_service_url'};
$GKey=		$Conf::conf{'jockeycall_banner_service_key'};
$GBannerBase=	$Conf::conf{'jockeycall_banner_base_path'};

if($Conf::disable_banners==1)
{
	print "Configuration error or banners disabled in configuration\n";
	exit 1;
}

$GBannerDefault=$GBannerBase.'/default';
$GBannerExtra=$GBannerBase.'/extra';
$GBannerMandatory=$GBannerBase.'/mandatory';

@GInfolines=();

foreach my $i(0..3){

	my $t=readline(STDIN);
	chomp $t;
	last if($t eq '-');
	$GInfoline[$i]=url_encode("$t");

}

# flip-default command

if($command eq 'flip-default'){

	$GChannel='default';
	print "for channel $GChannel:\n";
	add2set($GBannerMandatory,100,100);
	add2set($GBannerDefault,75,100);
	updateChannelInfo();

	}

# flip-channel command

if($command eq 'flip-channel'){

	$GChannel=$ARGV[1];
	if($GChannel eq ''){

		print "Channel not specified.\n";
		exit 0;

	}

	print "for channel $GChannel:\n";
	add2set($GBannerMandatory,100,100);
	add2set($GBannerDefault,5,10);

	if(-e "$GBannerBase/$GChannel"){

		add2set("$GBannerBase/$GChannel",25,75);

	}

	if(-e "$GBannerBase/$GChannel/mandatory"){

		add2set("$GBannerBase/$GChannel/mandatory",100,100);

	}

	$GShowBanners=$ARGV[2];

	if($GShowBanners ne ''){

		if(-e $GShowBanners){

			add2set("$GShowBanners",100,100);

		}
	}

	updateChannelInfo();

}

# update-info command

if($command eq 'update-info'){

        $GChannel=$ARGV[1];
        if($GChannel eq ''){

		print "Channel not specified.\n";
                exit 0;

        }

        print "Infolines Update	";
        $result=serviceInterface($GChannel,'11',$GInfoline[0],$GInfoline[1],$GInfoline[2],$GInfoline[3]);

}

# Subroutines

sub url_encode {
# https://www.perlmonks.org/?node_id=1179436
	my $rv = shift;
	$rv =~ s/([^a-z\d\Q.-_~ \E])/sprintf("%%%2.2X", ord($1))/geix;
	$rv =~ tr/ /+/;
	return $rv;
}

sub serviceInterface{

	$in_channel=$_[0];
	$in_op=$_[1];
	$in_p1=$_[2];
	$in_p2=$_[3]; $in_p3=$_[4]; $in_p4=$_[5];

	if($GCURLCMD eq ''){

		print "serviceInterface(): GCURLCMD global is null.\n";
		return;

	}

	if($GServiceURL eq ''){

		print "serviceInterface(): GServiceURL global is null.\n";
		return;

	}

	if($GKey eq ''){

		print "serviceInterface(): GKey global is null.\n";
		return;

	}

	if($in_channel eq ''){

		print "serviceInterface(): in_channel is null.\n";
		return;

	}

	if($in_op eq ''){

		print "serviceInterface(): in_op is null.\n";
		return;

	}

	my $c='';

	if($in_op eq '01'){

		$c="-d \"k=$GKey\" \"$GServiceURL?a=$in_op&c=$in_channel\"";

	}

	if($in_op eq '02'){

		$c="-d \"k=$GKey\" -d \"1=$_[2]\" -d \"2=$_[3]\" -d \"3=$_[4]\" -d \"4=$_[5]\" \"$GServiceURL?a=$in_op&c=$in_channel\"";
	}

	if($in_op eq '11'){

		$c="-d \"k=$GKey\" -d \"1=$_[2]\" -d \"2=$_[3]\" -d \"3=$_[4]\" -d \"4=$_[5]\" \"$GServiceURL?a=$in_op&c=$in_channel\"";
	}

        if($in_op eq '04'){

		$c="-d \"k=$GKey\" \"$GServiceURL?a=$in_op&c=$in_channel\"";

        }

	if($in_op eq '03'){

		if($in_p1 ne ''){

			$c="-F \"k=$GKey\" -F \"banner=\@$in_p1\" \"$GServiceURL?a=03&c=$in_channel\"";

		}

	}

	if($c eq ''){

		print "serviceInterface(): unsupported op \"$in_op\".\n";
		return

	}

	$output=qx/$GCURLCMD -sS $c/;
	$didItWork=scalar(grep('OK,',$output));

	if($didItWork==0){

		print "== FAILED ==	$in_p1\n";

	}else{

		print "ok		$in_p1\n";

	}

	return $didItWork;

}

sub updateChannelInfo{

	if($GChannel eq ''){

		print "updateChannelInfo(): GChannel is null.\n";
		return;

	}

	print "begin service calls ...\n";

	print "New		";
	$result=serviceInterface($GChannel,'01',$GChannel);
	return if($result==0);

	print "Infolines	";
	$result=serviceInterface($GChannel,'02',$GInfoline[0],$GInfoline[1],$GInfoline[2],$GInfoline[3]);

	my $n=0;

	foreach my $b(@GBanners){

		$n++;
		print "Send	".$n."/".scalar(@GBanners)."	";
		serviceInterface($GChannel,'03',$b);

	}

	print "Commit		";
	serviceInterface($GChannel,'04','');

}

sub add2set{

	$in_dir=$_[0];
	$in_lowpercent=$_[1];
	$in_highpercent=$_[2];

	if($in_dir eq ''){

		print "add2set(): in_dir is null.\n";
		return;

	}

	print "adding set $in_dir\n";
	
	my $p=$in_lowpercent+int(rand(($in_highpercent+1)-$in_lowpercent));
	my @d=();
	opendir(DIR,$in_dir);

	while(my $f=readdir(DIR)){

		next if($f =~ m/^\./);
		push(@d,"$in_dir/$f");

	}

	my @d2=shuffle @d;
	my $n=int(($p*scalar(@d2))/100);
	return if($n==0);

	for(my $i=0;$i<=($n-1);$i++){

		push(@GBanners,$d2[$i]);			

	}

}

