package DataMoving;
# SQLite backend
use DBI;
use parent 'Exporter';
use POSIX qw(strftime); # delete once entirely using sqlite
use File::Path qw(make_path); # needed for make_path(), delete once entirely using sqlite
require 'Conf.pm';
require 'Debug.pm';
require 'Concurrency.pm';

# Functions for dealing with persistent and external data
# SQLite backend

our @EXPORT=qw(
	setup
	setup_timeslot_vars
	get_candidate_tracks
	read_timeslot_dir
	read_schedule_dir
	read_file_string
	get_key
	set_key	
	get_rkey
	set_rkey
	clear_rkey
	append_to_list
	read_list
	oob_queue_dump
	oob_queue_pop
	oob_queue_push
	get_metadata
	set_metadata
        );

# My primary reference for everything database related here.
# https://www.tutorialspoint.com/sqlite/sqlite_perl.htm

# DBI error flag and subroutine to set it if something goes wrong.
my $dbi_setup_successfully=1;
sub dbi_error
{
# Sub is internal to this module

	Debug::error_out("DBI error: $DBI::errstr");
	$dbi_setup_successfully=0;
}


# Main needs to call this after it calls setdirs()
our $dbh_STATE;
our $dbh_METADATA;
sub setup
{
	# TODO: Handle failure better

	Debug::trace_out "*** DataMoving::setup() sqlite";
	my $db_op;
	my $rv;
	my %need_to_make;

	# --------------------------------------------------------------------
	# Get the state database ready
	Debug::trace_out "    DBI connect for state database: $Conf::conf{'basedir'}/$Conf::conf{'database'}";
	$dbh_STATE=DBI->connect_cached("DBI:SQLite:dbname=$Conf::conf{'basedir'}/$Conf::conf{'state_db'}",'','',{RaiseError=>1}) or
	 do
	{
		dbi_error;
		Concurrency::fail('state database (sqlite): initial DBI connect failed, unable to open or create it');
	};

	# The above will create the STATE database if it doesn't exist.
	# And if it is a new database, we have to create the tables.
	# So we need to query for existing tables and make the ones that are missing.
	#
	$db_op=$dbh_STATE->prepare("select name from sqlite_schema where type='table' order by name;");
	$rv=$db_op->execute() or dbi_error;
	if($rv<0){dbi_error;}
	#
	# State tables we're checking
	%need_to_make=('oob_queue'=>1,'rkeys'=>1);
	#
	# Fetch list of base state tables and mark 0 the ones that exist
	while(my @row=$db_op->fetchrow_array()){$need_to_make{$row[0]}=0;}
	#
	# For the ones that were left marked 1, make the base tables.
	#
	# We say base tables because we might have others that are created on-demand,
	# to track histories, but these are needed right off the bat for a new
	# database
	#
	if($need_to_make{'oob_queue'}==1)
	{
                Debug::trace_out('state database (sqlite): creating oob_queue table');
                my $stmt="
                create table 'oob_queue'
                 ( position	integer		primary key
                  ,track	text
                  );";
                my $rv=$dbh_STATE->do($stmt);
                if($rv<0){dbi_error;}
	}
	if($need_to_make{'rkeys'}==1)
	{
		Debug::trace_out('state database (sqlite): creating rkeys table');
	        my $stmt='
        	create table rkeys
	         ( name         text            primary key not null
        	  ,value        text
	          );';
        	my $rv=$dbh_STATE->do($stmt);
		if($rv<0){dbi_error;}
	}

	# --------------------------------------------------------------------
	# Get the metadata database ready
	Debug::trace_out "    DBI connect for metadata database: $Conf::conf{'basedir'}/$Conf::conf{'database'}";
        $dbh_METADATA=DBI->connect_cached("DBI:SQLite:dbname=$Conf::conf{'basedir'}/$Conf::conf{'metadata_db'}",'','',{RaiseError=>1}) or
         do
        {
                dbi_error;
                Concurrency::fail('metadata database (sqlite): initial DBI connect failed, unable to open or create it');
        };

        # The above will create the METADATA database if it doesn't exist.
        # And if it is a new database, we have to create the tables.
        # So we need to query for existing tables and make the ones that are missing.
        #
        $db_op=$dbh_METADATA->prepare("select name from sqlite_schema where type='table' order by name;");
        $rv=$db_op->execute() or dbi_error;
        if($rv<0){dbi_error;}
        #
        # Metadata tables we're checking, for metadata database
        %need_to_make=('metadata'=>1);
        #
        # Fetch list of base metadata tables and mark 0 the ones that exist
        while(my @row=$db_op->fetchrow_array()){$need_to_make{$row[0]}=0;}
        #
        # For the ones that were left marked 1, make the base tables.
        #
        # We say base tables because we might have others that are created on-demand,
        # to track histories, but these are needed right off the bat for a new
        # database
        #
	if($need_to_make{'metadata'}==1)
	{
		Debug::trace_out "metadata database (sqlite): creating metadata table";
	        my $stmt="
	        create table metadata
	         ( md5hash      	text            primary key not null
	          ,whenadded    	text		 
		  ,whenplayedlast	text
		  ,whereplayedlast	text
	          ,c_playcount  	int             not null
	          ,l_lengthsecs 	int             not null
	          ,w_weight     	int             not null
        	  );";
	        my $rv=$dbh_METADATA->do($stmt);
		if($rv<0){dbi_error;}
	}
}


our $timeslot_id='';
our $timeslot_vars_table='uninitialized';
sub setup_timeslot_vars
{
        Debug::trace_out "*** DataMoving::setup_timeslot_vars() sqlite";
#
# Parameters/info
#
# $_[0]: timeslot 1XXXX
#

	$timeslot_id=main::md5_hex($Conf::conf{'basedir'}.$_[0]);
        $timeslot_vars_table='timeslot_vars_'.$timeslot_id;

        Debug::trace_out "    timeslot_id is $timeslot_id";

        my $db_op=$dbh_STATE->prepare('select name from sqlite_schema where name=?;');
        my $rv=$db_op->execute($timeslot_vars_table) or dbi_error;
        if($rv<0){dbi_error;}
        while(my @row=$db_op->fetchrow_array())
        {
                if($row[0] eq $timeslot_vars_table)
                {
                        # table exists
                        Debug::trace_out "    existing table found";
                        return 1;
                }
        }

        # create new table for this timeslot_id
        Debug::trace_out "    creating new timeslot variables table $timeslot_vars_table";
        my $db_op=$dbh_STATE->prepare("select name from sqlite_schema where name=?;");
        my $stmt="
        create table \"$timeslot_vars_table\"
         ( name         text            primary key not null
          ,value        text
          );";
        my $rv=$dbh_STATE->do($stmt);
        if($rv<0){dbi_error; return 0;}
        set_key('directory',$Conf::conf{'SCD'});
        set_key('created',$Debug::timestamp_localtime);
        return 1;
}


sub track_filter
{
# Sub is internal to this module

# Parameters/info
#
# $_[0]: track name
# $_[1]: schedule zone, 0=green, 1=yellow, 2=red
#        we don't want to return .opr files if in yellow or red zone.
# 
# returns 1 if OK, 0 if caller should skip

	if( (lc(substr($_[0],-4)) eq '.mp3') ){return 1;}
	# Approve other file types here.
	if( (lc(substr($_[0],-4)) eq '.opr') ) 
	{
		if($_[1]==0)
		{
			Debug::trace_out "    track_filter filters() operation file \"".$_[0]."\" due to current schedule zone not being green.";
			return 1;
		}
		return 0;
	}
	Debug::trace_out "    track_filter() filters file \"".$_[0]."\" as unknown type.";
	return 0;
}

sub get_candidate_tracks
{
	Debug::trace_out "*** DataMoving::get_candidate_tracks($_[0]) sqlite";
# Parameters/info
#
# $_[0]: Directory containing timeslot tracks
# @{$_[1]}: History array
# @{$_[2]}: t trackname
# @{$_[3]}: h hash of track
# @{$_[4]}: c play count
# @{$_[5]}: l time of last play
# @{$_[6]}: w weight
# @{$_[7]}: z order
# $_[8]: difference
# $_[9]: schedule zone, 0=green, 1=yellow, 2=red
#        we don't want to return .opr files if in yellow or red zone.
#
# Goes through a list of timeslot tracks, eliminates tracks that are
#  found in a provided history array, and then pushes various data in
#  provided arrays.
#
# The arrays can be then sorted using various criteria and then a used
#  to select a track for delivery.
#
# Returns $flag_dup.  This is 0 if no tracks were eliminated because
#  they were found in the history.  If no candidate tracks are returned
#  at all, then $flag_dup being 0 means that no tracks will fit in the
#  remaining time left in the timeslot.
#
	my $trackdir="$_[0]";

        my $n=0;
        my $cc=0; my $cl=0; my $cw=0;
        my $flag_dup=0;

	opendir my $d,$trackdir or Concurrency::fail("opendir failed on $trackdir");

	while(my $f=readdir($d))
	{
		# Filter all tracks through this function
		if(track_filter($f,$_[9]))
		{

			my $md5hash=MetadataProcess::metadata_process("$trackdir/$f",\@{$_[1]},\$cc,\$cl,\$cw,\$flag_dup);
			next if($md5hash eq '0');
			# check if we would have enough time in this timeslot
			# to play this.
			# If time does not matter, such as for the
			#  intermission, 99999 should be used.
			if($cl>($_[8]*60))
			{
       	        		 Debug::trace_out
				 "    disqualified $md5hash because it's ".($cl-($_[8]*60))." seconds longer than end of timeslot.";
				next;	
			}
			push @{$_[2]},$f;
			push @{$_[3]},$md5hash;
			push @{$_[4]},$cc;
			push @{$_[5]},$cl;
			push @{$_[6]},$cw;
			push @{$_[7]},$n;
			Debug::trace_out("    candidate track $n: $md5hash, $f, C:$cc, L:$cl, W:$cw");
			$n++;
		}
	}
	closedir $d;

	return $flag_dup;
}


sub read_timeslot_dir
{
Debug::trace_out "*** DataMoving::read_timeslot_dir($_[0],$_[1],$_[2]) sqlite";

# Parameters/info
#
# $_[0]: Directory containing timeslot
# @{$_[1]}: Reference to array that should hold t-dirs from timeslots
# @{$_[2]}: Reference to array that holds timeslot directory history
#
# Reads the t-dirs in a timeslot directory and puts them in an array.
#
# If directory is found in timeslot directory history, it won't be pushed on
# @{$_[1])
#
	opendir my $d,"$_[0]" or Concurrency::fail("opendir failed on $_[0]");

	while(my $f=readdir($d))
	{
# Reject subdirs that don't start with 't-'
	        next if(substr($f,0,2) ne 't-');
# Reject files that aren't a directory
	        my $d1f="$_[0]/$f";
		next if(! -d $d1f);
	        if(grep( /^$d1f$/,@{$_[2]}))
		{
			next
		}
	        Debug::trace_out "    push $d1f";
   		push @{$_[1]},"$d1f";
	}
	closedir $d;
	Debug::debug_out("    ".scalar(@{$_[1]})." dir(s) found in $_[0]");
}

sub read_schedule_dir
{
Debug::trace_out "*** DataMoving::read_schedule_dir($_[0])";

# Parameters/info
#
# $_[0]: Directory containing schedule 
# @{$_[1]}: Reference to array that should hold timeslots from schedule
#
# Reads the timeslots in the schedule and puts them in an array
#
	opendir my $d,"$_[0]" or Concurrency::fail("unable to open \"$_[0]\"");
	while(my $f=readdir($d))
	{
	# Skip unwanted things
		next if($f eq '.'); next if($f eq '..');
		next if(! -d "$_[0]/$f");
		next if(length($f)!=5); # if not 5 characters long
		next if(! $f =~ /^[:digit:]+/); # if not numeric
		push @{$_[1]},$f;
	}
	closedir $d;
	Debug::debug_out("    ".scalar(@{$_[1]})." dir(s) found in $_[0]");
}

sub read_file_string
{
Debug::trace_out "*** DataMoving::read_file_string($_[0]) sqlite";

# Parameters/info
#
# $_[0]: File to read, will NOT be created if it does not exist
#
# Returns text of file, or undef if file doesn't exist or an I/O error
# occurred.
#
# This is primarily used to read the text files that contain the channel's
# description.

	my $in_file="$_[0]";
	return undef if($in_file eq '');

	if(! -e $in_file)
	{
		Debug::trace_out "    read_file_string($_[0]): file not found, returning undef";
		return undef;
	}
	
	open(my $f,'<',$in_file) or
	do{
		Debug::error_out
		 "[read_file_string] unable to open $in_file for reading";
		return "";
	};

	my $file_contents=<$f>;

	Debug::trace_out "    read_file_string($_[0]): data \"$_[1]\"";

	close($f); chomp $file_contents; return $file_contents;
} 


sub get_key
{
	Debug::trace_out "*** DataMoving::get_key(\"$_[0]\",\"$_[1]\") sqlite";
	return $_[1] if($_[0] eq '');

# Parameters/info
#
# $_[0]: Timeslot-level variable to read from database;, will be created if it
#        does not exist.
# $_[1]: Default value, if value doesn't exist, $_[1] will be echoed backl and
#        that value will be written to the variable.
#
# Returns text of timeslot-level variable, or $_[1] if:
#  - timeslot-level variable was new
#  - $_[0] was null
#  - a database error occurred and the variable could not be read
#
        my $db_op=$dbh_STATE->prepare('select value from "'.$timeslot_vars_table.'" where name=?;');
        my $rv=$db_op->execute($_[0]);
        if($rv<0)
        {
                dbi_error;
                Debug::error_out "[DataMoving::get_key sqlite] unable to get variable $_[0] from $timeslot_vars_table";
                return $_[1];
        }

        my $data; my $rows=0;
        # we are looping through rows but there should be only one row.
        # something is wrong if there's more than one.
        while(my @row=$db_op->fetchrow_array())
        {
                $rows++;
                if($rows>1)
                {
                        Debug::error_out "[DataMoving::get_key sqlite] multiple variable with same name in $timeslot_vars_table, database is bad";
                        return $_[1];
                }
                $data=$row[0];
        }

        if(!$data)
        {
		Debug::trace_out "    get_key variable \"$_[0]\" doesn't exist in database";
		Debug::trace_out "    will return default value supplied in call as read value";
                # if the default value for a variable is nothing, no point in
                # issuing an initial write.
		if($_[1] eq '')
		{
			Debug::trace_out "    get_key didn't write anything because the default value is null";
                	return $_[1];
		}

                Debug::trace_out "    get_key writes new variable \"$_[0]\" with default value suppled in call, \"$_[1]\"";
                set_key($_[0],$_[1]);
                return $_[1];
        }else{
                Debug::trace_out "    get_key reads \"$data\" for variable \"$_[0]\" in \"$timeslot_vars_table\"";
                return $data;
        }
}


sub get_rkey
{
	Debug::trace_out "*** get_rkey(\"$_[0]\",\"$_[1]\") sqlite";
	return $_[1] if($_[0] eq '');

# Parameters/info
#
# $_[0]: Root-level variable to read from database;  will be created if it
#        does not exist.
# $_[1]: Default value, if variable doesn't exist this will be returned and
#        written.
#
# Root-level variables are not timeslot specific and can be used before the
# timeslot is known.
#
# Returns value of root-level variable, or echoes back $_[1] if:
#  - root-level variable was new
#  - $_[0] was null
#  - a database error occurred and the variable could not be read
#
	my $db_op=$dbh_STATE->prepare('select value from rkeys where name=?;');
	my $rv=$db_op->execute($_[0]);
        if($rv<0)
        {
                dbi_error;
                Debug::error_out "[DataMoving::get_rkey sqlite] multiple root keys with same name in rkeys, database is bad";
                return $_[1];
        }

	my $data; my $rows=0;
	# we are looping through rows but there should be only one row.
	# something is wrong if there are more than one.
	while(my @row=$db_op->fetchrow_array())
	{
		$rows++;
		if($rows>1)
		{
                	Debug::error_out "[DataMoving::get_rkey sqlite] multiple keys with same name, database is bad";
			return $_[1];
		}	
		$data=$row[0];	
	}

	if(!$data)
	{
		# if the default value for a key is nothing, no point in
		# issuing an initial write.
		return $_[1] if($_[1] eq '');

                Debug::trace_out "    get_rkey writes new root key \"$_[0]\" with default value \"$_[1]\"";
		set_rkey($_[0],$_[1]);
		return $_[1];
	}else{
                Debug::trace_out "    get_rkey reads \"$data\" for root key \"$_[0]\" in rkeys";
		return $data;
	}
}


sub set_key
{
	Debug::trace_out "*** DataMoving::set_key(\"$_[0]\",\"$_[1]\") sqlite";
	return 0 if($_[0] eq '');

# Parameters/info
#
# $_[0]: Timeslot-level variable to write to database
# $_[1]: Data to write
#
# Returns 1 if successful, 0 if an I/O error occurred
#
        my $db_op=$dbh_STATE->prepare('insert or replace into "'.$timeslot_vars_table.'" (name,value) values (?,?);');
        $db_op->execute($_[0],$_[1]);
        if($rv<0)
        {
                dbi_error;
                Debug::error_out "[DataMoving::set_key sqlite] unable to set variable $_[0] in $timeslot_vars_table";
                return 0;
        }

        return 1;
}


sub set_rkey
{
	Debug::trace_out "*** DataMoving::set_rkey(\"$_[0]\",\"$_[1]\") sqlite";
	return 0 if($_[0] eq '');

# Parameters/info
#
# $_[0]: Root-level variable to write to database
# $_[1]: Value to put into variable
#
# Root-level variables are not timeslot specific and can be used before the
# timeslot is known.
#
# Returns 1 if successful, 0 if an I/O error occurred or $_[0] is null.
#
        my $db_op=$dbh_STATE->prepare('insert or replace into rkeys (name,value) values (?,?);');
        $db_op->execute($_[0],$_[1]);
        if($rv<0)
        {
                dbi_error;
                Debug::error_out "[DataMoving::set_key sqlite] unable to set root variable $_[0]";
                return 0;
        }

	return 1;
}


sub clear_rkey
{
	Debug::trace_out "*** DataMoving::clear_rkey(\"$_[0]\") sqlite";
	return 0 if($_[0] eq '');
#
# Parameters/info
#
# $_[0]: Root-level variable to clear from database
#
# Root-level variables are not timeslot specific and can be used before the
# timeslot is known.
#
# Returns 1 if successful, 0 if an I/O error occurred or $_[0] is null.
# This deletes the variable from the database
#
	my $db_op=$dbh_STATE->prepare('delete from rkeys where name=?;');
	$db_op->execute($_[0]);
        if($rv<0)
        {
                dbi_error;
                Debug::error_out "[DataMoving::clear_key sqlite] unable to clear root variable $_[0]";
                return 0;
        }

        return 1;
}

my %known_tables;
sub make_table_if_needed
{
	Debug::trace_out "*** DataMoving::make_table_if_needed(\"$_[0]\") sqlite";
# Sub is internal to this module
#
# Parameters/info
#
# $_[0]: Table name to check
#        This should be 'list-'.$_[0].'-'.$timeslot_id
#
# Returns:
# - 0 if a DBI error occurred.
# - 1 if an existing table was found or remembered.
# - 2 if a new table was just created.
#
	if($known_tables{$_[0]}==1)
	{
		Debug::trace_out "    Remembering table \"$_[0]\" exists from earlier";
		return 1;
	}

        my $db_op=$dbh_STATE->prepare('select name from sqlite_schema where name=?;');
        my $rv=$db_op->execute($_[0]) or dbi_error;
        if($rv<0){dbi_error;}
        while(my @row=$db_op->fetchrow_array())
        {
                if($row[0] eq $_[0])
                {
                        # table exists
                        Debug::trace_out "    existing table for \"$_[0]\" found, using it";
			$known_tables{$_[0]}=1;
                        return 1;
                }
        }

        # create new table for this timeslot_id
        Debug::trace_out "    need to make new table \"$_[0]\"";
        my $db_op=$dbh_STATE->prepare('select name from sqlite_schema where name=?;');
        my $stmt="
        create table \"$_[0]\"
         ( id		integer		primary key 
          ,value	text		not null
          );";
        my $rv=$dbh_STATE->do($stmt);
        if($rv<0)
	{
		dbi_error;
		return 0;
	}

	$known_tables{$_[0]}=1;
	return 2;
}


sub new_list
{
	Debug::trace_out "*** DataMoving::new_list(\"$_[0]\") sqlite";
	return 0 if($_[0] eq '');
# Parameters/info
#
# $_[0]: List to create; if list exists, it will be cleared.
#
# Returns 1 if successful, 0 if a DBI error occurred
#
	my $list_table='list_'.$_[0].'_'.$timeslot_id;

	my $t=make_table_if_needed($list_table);

	# If make_table_if_needed() ran into a problem, forward that up.
	if($t==0){return 0;}

	# Did make_table_if_needed() make a new table?  Then it's empty.
	# Let's return and report success.
	if($t==2){return 1;}

	# Otherwise...
	# At this point we're looking at clearing an existing table.
	my $rv=$dbh_STATE->do('delete from "'.$list_table.'"');
	if($rv<0)
        {
                dbi_error;
                Debug::error_out "[DataMoving::new_list sqlite] DBI error during delete in table for list \"$_[0]\"";
                return 0;
        }
	return 1;
}


sub new_rlist
{
        Debug::trace_out "*** DataMoving::new_rlist(\"$_[0]\") sqlite";
        return 0 if($_[0] eq '');
# Parameters/info
#
# $_[0]: Root list to create; if root list exists, it will be cleared.
#
# Returns 1 if successful, 0 if a DBI error occurred
#
        my $list_table='rlist_'.$_[0];

        my $t=make_table_if_needed($list_table);

        # If make_table_if_needed() ran into a problem, forward that up.
        if($t==0){return 0;}

        # Did make_table_if_needed() make a new table?  Then it's empty.
        # Let's return and report success.
        if($t==2){return 1;}

        # Otherwise...
        # At this point we're looking at clearing an existing table.
        my $rv=$dbh_STATE->do('delete from "'.$list_table.'"');
        if($rv<0)
        {
                dbi_error;
                Debug::error_out "[DataMoving::new_rlist sqlite] DBI error during delete in table for root list \"$_[0]\"";
                return 0;
        }
        return 1;
}


sub append_to_list
{
	Debug::trace_out "*** DataMoving::append_to_list(\"$_[0]\",\"$_[1]\") sqlite";
	if($_[0] eq '')
	{
		Debug::trace_out "    first parameter null, returning error";
		return 0;
	}
	if($_[1] eq '')
	{
		Debug::trace_out "    second parameter null, returning success";
		return 1;
	}
# Parameters/info
#
# $_[0]: List to append to; list will be created (sqlite table) if needed.
# $_[1]: String to append
#
# Returns 1 if successful, 0 if an DBI error occurred
#
	my $list_table='list_'.$_[0].'_'.$timeslot_id;
	return 0 if(make_table_if_needed($list_table)==0);
	Debug::trace_out "    make_table_if_needed returned without error";

        my $db_op=$dbh_STATE->prepare('insert into "'.$list_table.'" (value) values (?);');
	# We're not setting 'id' column here because ...
	#
	# This--https://sqlite.org/autoinc.html--tells me it will autoincrement
	# without us having to do anything.
	#
	# Which is what we want-we may want to retrieve a list based on the order
	# added.
        $db_op->execute($_[1]);
        if($rv<0)
        {
                dbi_error;
                Debug::error_out "[DataMoving::append_to_list sqlite] DBI error during insert \"$[1]\" in table for list \"$_[0]\"";
                return 0;
        }
}


sub append_to_rlist
{
        Debug::trace_out "*** DataMoving::append_to_rlist(\"$_[0]\",\"$_[1]\") sqlite";
        if($_[0] eq '')
        {
                Debug::trace_out "    first parameter null, returning error";
                return 0;
        }
        if($_[1] eq '')
        {
                Debug::trace_out "    second parameter null, returning success";
                return 1;
        }
# Parameters/info
#
# $_[0]: Root list to append to; root list will be created (sqlite table) if
#        needed.
# $_[1]: String to append
#
# Returns 1 if successful, 0 if an DBI error occurred
#
        my $list_table='rlist_'.$_[0];
        return 0 if(make_table_if_needed($list_table)==0);
        Debug::trace_out "    make_table_if_needed returned without error";

        my $db_op=$dbh_STATE->prepare('insert into "'.$list_table.'" (value) values (?);');
        # We're not setting 'id' column here because ...
        #
        # This--https://sqlite.org/autoinc.html--tells me it will autoincrement
        # without us having to do anything.
        #
        # Which is what we want-we may want to retrieve a list based on the order
        # added.
        $db_op->execute($_[1]);
        if($rv<0)
        {
                dbi_error;
                Debug::error_out "[DataMoving::append_to_rlist sqlite] DBI error during insert \"$[1]\" in table for rlist \"$_[0]\"";
                return 0;
        }
	return 1;
}


sub read_list
{
	Debug::trace_out "*** DataMoving::read_list(\"$_[0]\") sqlite";
# Parameters/info
#
# $_[0]: List to read, will be created if it does not exist.
# Returns array of lines in list.
#
# Returns undef if list is empty or an I/O error occurred.
#
	my $list_table='list_'.$_[0].'_'.$timeslot_id;
	return 0 if(make_table_if_needed($list_table)==0);
	Debug::trace_out "    make_table_if_needed returned without error";

        my $db_op=$dbh_STATE->prepare('select value from "'.$list_table.'";');
	my $rv=$db_op->execute();
        if($rv<0)
        {
                dbi_error;
                Debug::error_out "[DataMoving::read_list sqlite] DBI error during select on table for list \"$_[0]\"";
		return @empty_list=undef;
        }

        my @rows_of_data;
        while(my @row=$db_op->fetchrow_array())
        {
		push @rows_of_data,@row;
        }

	Debug::trace_out "    existing list ".scalar(@rows_of_data)." lines";
	return @rows_of_data;
}


sub read_rlist
{
        Debug::trace_out "*** DataMoving::read_rlist(\"$_[0]\") sqlite";
# Parameters/info
#
# $_[0]: Root list to read, will be created if it does not exist.
# Returns array of lines in list.
#
# Returns undef if list is empty or an DBI error occurred.
#
        my $list_table='rlist_'.$_[0];
        return 0 if(make_table_if_needed($list_table)==0);
        Debug::trace_out "    make_table_if_needed returned without error";

        my $db_op=$dbh_STATE->prepare('select value from "'.$list_table.'";');
        my $rv=$db_op->execute();
        if($rv<0)
        {
                dbi_error;
                Debug::error_out "[DataMoving::read_rlist sqlite] DBI error during select on table for rlist \"$_[0]\"";
                return @empty_list=undef;
        }

        my @rows_of_data;
        while(my @row=$db_op->fetchrow_array())
        {
                push @rows_of_data,@row;
        }

        Debug::trace_out "    existing rlist ".scalar(@rows_of_data)." lines";
        return @rows_of_data;
}


sub oob_queue_dump
{
# Parameters/info
#
# Dumps OOB queue to STDOUT.
#
# Intended for use by oob dump subcommand.
#
	Debug::trace_out "*** DataMoving::oob_queue_dump() sqlite";
	my $db_op=$dbh_STATE->prepare('select "position","track" from "oob_queue" order by "position" desc;');
	my $rv=$db_op->execute();
        if($rv<0)
        {
                dbi_error;
                Debug::error_out "[DataMoving::oob_queue_dump sqlite] DBI error during select";
                return undef;
        }
	my $printed_anything=0;
        while(my @row=$db_op->fetchrow_array())
        {
		$printed_anything=1;
		print "$row[0]	: $row[1]\n"
        }
	if(!$printed_anything)
	{
		print "OOB queue is empty\n";
	}
        return 1;
}


sub oob_queue_push
{
# Parameters/info
#
# $_[0]: Track path (full path expected) to push onto OOB queue.
#
# Returns 1 if track pushed successfully, 0 if not.
#
	Debug::trace_out "*** DataMoving::oob_queue_push(\"$_[0]\") sqlite";
	if($_[0] eq '')
	{
		Debug::trace_out "    first parameter was null, doing nothing";
		return 1;
	}

        my $db_op=$dbh_STATE->prepare('insert into "oob_queue" (track) values (?);');
        # We're not setting 'id' column here because ...
        #
        # This--https://sqlite.org/autoinc.html--tells me it will autoincrement
        # without us having to do anything.
        #
        # Which is what we want-we may want to retrieve a list based on the order
        # added.
        $db_op->execute($_[0]);
        if($rv<0)
        {
                dbi_error;
                Debug::error_out "[DataMoving::oob_queue_push sqlite] DBI error during insert of track \"$[0]\" to OOB queue";
                return 0;
        }
	return 1;
}


sub oob_queue_pop
{
	Debug::trace_out "*** DataMoving::oob_queue_pop sqlite";
# Parameters/info
#
# Takes no arguments.  Will pop most recent OOB track pushed on to stack, or
# returns undef if stack is empty or an error occured.
#
	my $db_op=$dbh_STATE->prepare('select "position","track" from "oob_queue" order by "position" desc;');
	my $rv=$db_op->execute();
	if($rv<0)
	{
		dbi_error;
		Debug::error_out "[DataMoving::oob_queue_pop sqlite] DBI error during select";
		return undef;
	}
	my $out=undef;
	while(my @row=$db_op->fetchrow_array())
	{
		$out=$row[1];
		Debug::trace_out "    top row is \"$row[0]\", \"$row[1]\"";
		my $db_op=$dbh_STATE->prepare('delete from "oob_queue" where position=?');
		$rv=$db_op->execute($row[0]);
		if($rv<0)
		{
			dbi_error;
			Debug::error_out "[DataMoving::oob_queue_pop sqlite] DBI error during delete of track \"$row[1]\" from OOB queue position $row[0]";
		}
		last;
	}
	if($out eq ''){return undef;}
	return $out;
}


sub get_metadata
{
	Debug::trace_out "*** DataMoving::get_metadata($_[0])";
# Parameters/info
#
# $_[0]: md5
#
# Returns undef if an DBI error occurred.
#
	my %out_metadata=(c=>0,l=>0,w=>0);
	# If l is 0, MetadataProcess::metadata_process will call mp3info to
	# set the length.

        my $db_op=$dbh_METADATA->prepare('select c_playcount,l_lengthsecs,w_weight from metadata where md5hash=?');
        my $rv=$db_op->execute($_[0]);
        if($rv<0)
        {
                dbi_error;
                Debug::error_out "[DataMoving::get_metadata sqlite] unable to get metadata of $_[0] from metadata table";
                return $_[1];
        }

        my $rows=0;
        while(my @row=$db_op->fetchrow_array())
        {
                $rows++;
                if($rows>1)
                {
                        Debug::error_out "[DataMoving::get_metadata sqlite] multiple keys with same md5 in metadata table, database is bad";
                        return undef;
                }
		%out_metadata=(c=>$row[0],l=>$row[1],w=>$row[2])
        }

	return %out_metadata;
}


sub set_metadata
{
	Debug::trace_out "*** DataMoving::set_metadata($_[0],$_[1]) sqlite";
# Parameters/info
#
# $_[0]: md5
# $_[1]: data to write; should be a reference to a hash
#
# Returns 1 if written successfully, 0 if an DBI error occurred
#
        my $db_op=$dbh_METADATA->prepare('insert or replace into metadata (md5hash,c_playcount,l_lengthsecs,w_weight) values (?,?,?,?)');
        $db_op->execute($_[0],$_[1]->{'c'},$_[1]->{'l'},$_[1]->{'w'});
        if($rv<0)
        {
                dbi_error;
                Debug::error_out "[DataMoving::set_metadata sqlite] unable to set metadata for $_[0]";
                return 0;
        }

	return 1;
}

if($dbi_setup_successfully!=1){0;}else{1;}
