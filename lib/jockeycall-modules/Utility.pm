package Utility;
use parent 'Exporter';

# Utility/computation functions

our @EXPORT=qw(
	usage
	datestring_to_human_readable_time
	check_datestring
	datestring_to_minutes
	minutes_to_datestring
        );

sub usage
{
#
# Outputs usage information
#
	print "This is Jockeycall.\n";
	print "\n";
	print "I need ...\n";
	print "- at least one command-line argument--the subcommand--and the\n";
	print "  JOCKEYCALL_CHANNEL environment variable defined, which should be your\n";
	print "  channel directory\n";
	print "  ... or ...\n";
	print "- if the subcommand is 'transmit', the command-line argument after that\n";
	print "  needs to be the channel directory.\n";
	print "\n";
	print "To do the environment variable stuff above from bash, try:\n";
	print "$ export JOCKEYCALL_CHANNEL=/dir/to/channel $0 {subcommand} {parameters}\n";
}

sub datestring_to_human_readable_time
{
	if(!check_datestring){return 'INVALID';}
	my $s1=int(substr($_[0],1,2));
	if($s1==0){$s1=12;}
	if($s1>12){$s1-=12;$s3='p'}else{$s3='a';}
	if($s1<10){$s1="$s1";}
	my $s2=substr($_[0],3,2);
	$s4=$s1.':'.$s2.$s3;
	return $s4;
}

sub check_datestring
{
# Parameters/info
#
# Checks input to ensure datestring is valid
# $_[0]: Datestring
# Returns 1 if OK, 0 if not

	# must be 5 chars
	if(length($_[0])!=5){return 0;}
	# first digit must be 1
	if(substr($_[0],0,1) ne '1'){return 0;}
	# digits 2 and 3 must be 00-23
	my $v=(int(substr($_[0],1,2)));
	if(($v>23)or($v<0)){return 0;}
	# digits 4 and 5 must be 00-59
	$v=(int(substr($_[0],3,2)));
	if(($v>59)or($v<0)){return 0;}
	return 1;
}

sub datestring_to_minutes
{
# Parameters/info
#
# Converts 1HHMM to minutes
# $_[0]: 1HHMM
# Returns minutes
	my $x=shift; my $t=$x-10000; my $t2=int($t/100)*60; my $t3=$t-((int($t/100))*100); my $t4=$t2+$t3; return ($t4);
}

sub minutes_to_datestring
{
# Parameters/info
#
# Converts minutes to 1HHMM
# $_[0]: Minutes
# Returns 1HHMM

	my $x=shift; my $t=int($x/60); my $t2=$x-($t*60); if($t<10){$t='0'.$t;} if($t2<10){$t2='0'.$t2;} return ('1'.$t.$t2);
}

1;
