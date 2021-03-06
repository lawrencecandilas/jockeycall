package Events;
use parent 'Exporter';
require 'Debug.pm';
require 'Conf.pm';
require 'Concurrency.pm';
require 'Playlog.pm';
require 'DataMoving.pm';
require 'DeliverTrack.pm';

# Functions called when specific things happen

our @EXPORT=qw(
	entering_new_timeslot
	entering_intermission
	leaving_intermission
	entering_new_day
	timeslot_portion
        );


sub entering_new_day
{
	Debug::trace_out "*** entering_new_day($_[0],$_[1])";

# Parameters/info
#
# Called when entering new day
#
# $_[0]: Current (new) day number
# $_[1]: Previous day number
#
# Note: Schedule directory is not established at the time this event might be
# called!

        if($ENV{'JOCKEYCALL_SIMULATION_MODE'}==1)
        {
                print "[== New Day ==] ";
        }
	Playlog::private_playlog_out('== New Day ==');
}


sub entering_new_dow
{
        Debug::trace_out "*** entering_new_day($_[0],$_[1])";

# Parameters/info
#
# Called when entering new day
#
# $_[0]: Current (new) DOW number
# $_[1]: Previous DOW number
#
# Note: Schedule directory is not established at the time this event might be
# called!

	my @weekday=('Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday');
        if($ENV{'JOCKEYCALL_SIMULATION_MODE'}==1)
        {
        	print "[== It\'s ".$weekday[$_[1]]." ==] ";
        }
        Playlog::private_playlog_out("== It\'s ".$weekday[$_[1]]." ==");
}


sub entering_new_timeslot
{
	Debug::trace_out "*** entering_new_timeslot($_[0])";

# Parameters/info
#
# Called when entering new timeslot
#
# $_[0]: New timeslot

        if($ENV{'JOCKEYCALL_SIMULATION_MODE'}==1)
        {
                print "[== New Timeslot ==] ";
        }
        Debug::debug_out('entering new timeslot');
        BannerUpdate::set_doUpdate_flag();
        DataMoving::set_rkey('need-a-flip','');
	Playlog::private_playlog_out('== New Timeslot ==');
}


sub entering_intermission
{
	Debug::trace_out "*** entering_intermission()";

# Parameters/info
#
# Called when entering intermission

        Debug::debug_out('entering new timeslot');
        BannerUpdate::set_doUpdate_flag();
        DataMoving::set_rkey('need-a-flip','');


        if($ENV{'JOCKEYCALL_SIMULATION_MODE'}==1)
        {
                print "[== Entering Intermission ==] ";
        }
	Playlog::private_playlog_out('== Entering Intermission ==');
	Playlog::public_playlog_out('(Now in intermission)');
}


sub leaving_intermission
{
	Debug::trace_out('*** leaving_intermission()');

# Parameters/info
#
# Called when leaving intermission

	if($ENV{'JOCKEYCALL_SIMULATION_MODE'}==1)
	{
		print "[== Leaving Intermission ==] ";
	}
	Playlog::private_playlog_out('== Leaving Intermission ==');
	Playlog::public_playlog_out('(Back to program)');
}


sub timeslot_zone
{
	Debug::trace_out("*** timeslot_zone($_[0],$_[1],$_[2],$_[3])");

# Parameters/info
#
# Called at various points in the timeslot
# $_[0] is zone code
#	1: Schedule in yellow zone
#	2: Schedule in red zone
# $_[1] is current timeslot
# $_[2] is next timeslot
# $_[3] is difference (minutes remaining in timeslot)

	if($_[0]==1)
	{
	        if($ENV{'JOCKEYCALL_SIMULATION_MODE'}==1)
        	{
                	print "[== Schedule Yellow Zone ==] ";
	        }
		Playlog::private_playlog_out('== Schedule Yellow Zone ==');
	}
	if($_[0]==2)
	{
                if($ENV{'JOCKEYCALL_SIMULATION_MODE'}==1)
                {
                        print "[== Schedule Red Zone ==] ";
                }
		Playlog::private_playlog_out('== Schedule Red Zone ==');
	}

}

1;
