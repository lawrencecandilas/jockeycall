package HTMLSchedule;
use parent 'Exporter';
require 'Debug.pm';
require 'Conf.pm';
require 'Utility.pm';
require 'DataMoving.pm';

# Generate HTML schedule

our @EXPORT=qw(
	html_schedule
        );

sub html_schedule
{
	Debug::trace_out "*** html_schedule(\"".$_[0]."\")";
#
# Returns big string containing HTML version of the schedule
#
	my $o='';

	$o=$o.'<div class="jockeycall-schedule">';

	if($_[0] eq '')
	{
		Debug::error_out 'html_schedule(): $_[0] was null, cannot do very much for you';
		goto skip_1;
	}

	$in_channel=$_[0];

	$o=$o.'<div class="jockeycall-channel-schedule-title">'.$in_channel." schedule</div>";
	$o=$o.'<table class="jockeycall-schedule-table">';

	my @schedule=();
	my $scd="$Conf::conf{'basedir'}/$Conf::conf{'schedules_at'}";
	DataMoving::read_schedule_dir($scd,\@schedule);

	if(scalar(@schedule)==0)
	{
		$o=$o.'</table>';
		$o=$o.'<div class="jockeycall-channel-notice">Check Back Later for Show Schedules</div>';
		$o=$o.'</div>';
		return $o;
	}
	
	my @schedule_sorted=sort{$a<=>$b} @schedule;

	my $n=@schedule_sorted;
	while($n!=0)
	{	
		if(int(@schedule_sorted[0])<10500)
		{
			my $x=shift @schedule_sorted;
			push @schedule_sorted,$x;
			$n--;
		}
		else
		{
			last;
		}
	}

	my $this_timeslot;
	foreach $this_timeslot(@schedule_sorted)
	{
		$o=$o.'<tr class="jockeycall-schedule-line">';
		if(scalar(@schedule_sorted)==1)
		{
			$o=$o.'<td class="jockeycall-schedule-time">All day</td>';
		}
		else
		{
			$o=$o.'<td class="jockeycall-schedule-time">'.Utility::datestring_to_human_readable_time($this_timeslot).'</td>';
		}

		$tsd="$scd/$this_timeslot";
		$if="$tsd/info/showTitle.txt";

		if(-e $if)
		{
			$ifc=qx/cat $if/;
			if($?!=0){$ifc="Scheduled Programming"}
		}
		else
		{
			$ifc="To Be Announced";
		}

		$o=$o.'<td class="jockeycall-schedule-show">'.$ifc.'</td>';
		$o=$o.'</tr>';
	}


	$o=$o.'</table>';

skip_1:
	$o=$o.'</div>';

	return $o;
}

1;
