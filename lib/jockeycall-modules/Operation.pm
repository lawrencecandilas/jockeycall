package Operation;
use parent 'Exporter';
#use POSIX qw(strftime);
use List::Util 'any';
require 'Debug.pm';
require 'Conf.pm';
require 'Concurrency.pm';
require 'DataMoving.pm';
require 'DeliverTrack.pm';
require 'Utility.pm';
require 'MetadataProcess.pm';


our @EXPORT=qw(
	kickoff
	one_step
	cancel_any_active
	process_any_active
        );


my @valid_operation_names=(
	'playall'
	);


# Cancelled flag
my $cancelled=0;

# Channel, main should set this ...
our $channel;

# ... using this convenient method.
# I wrote a note about why this is here in OOB.pm.  Same deal.
sub set_channel
{
        Debug::trace_out("*** Operation::set_channel(\"$_[0]\")");
        $channel=$_[0];
        return 1;
}


sub kickoff
{
        Debug::trace_out("*** Operation::kickoff(\"".$_[0]."\")");

# Parameters/info
#
# $_[0]: Full path of operation file (what was handed to DeliverTrack())
#
# This will kick off an operation as described in an .opr file.
# DeliverTrack() will call this when an .opr file passes through it, so we are
# at the point where we're almost ready to deliver a track.
#
# Returning from this function will make DeliverTrack() call
# technical_difficulties().

	one_step($_[0],0);
}


sub get_total_duration
{
	Debug::trace_out("*** Operation::get_duration(\"".$_[0]."\")");

# Parameters/info
#
# $_[0]: Full path of operation file 
#
# Loops through an operation and calls get_step_estimated_duration() on each
# step, then returns the total.

}


sub read_opr_file
{
	my %opr_file_data;

        # file doesn't exist? report error and return.
        if(! -e $_[0])
        {
                Debug::error_out("[Operation::one_step] operation file \"".$_[0]."\" doesn't exist.");
                cancel_any_active;
                return undef;
        }

	my @oprsteplist;

        open(my $oprfilehandle,'<',$_[0]); ##or Concurrency::fail "open of $oprfilehandle failed";
        while(<$oprfilehandle>)
        {
                my $line=$_;
                $line=~s/^\s+|\s+$//g;

                next if($line eq ''); # skip blank lines
                next if($line =~ /^\s*#/); # skip lines beginning with # - comments

                # If %opr_file_data{'name'} is null then we're looking for a line
                # that has the operation command
                if(!$opr_file_data{'name'})
                {
                        my @oprparams=split(/ /,$line);
                        $opr_file_data{'name'}=shift @oprparams;
                        if(!(any{/$opr_file_data{'name'}/}@valid_operation_names))
                        {
                                Debug::error_out("[Operation::one_step] the command \"".$opr_file_data{'name'}."\" in operation file \"".$_[0]."\" is not recognized.");
                                cancel_any_active;
                                return 1;
                        }
			$opr_file_data{'params'}=@oprparams;
                        next;
                }

                # If $current_operation is not null then we're looking at steps
                # and we can go ahead and shove them into the array.
                push(@oprsteplist,$line);
        }
        close($oprfilehandle);

	$opr_file_data{'steplist'}=@oprsteplist;

	return %opr_file_data;
}


sub one_step
{
        Debug::trace_out("*** Operation::one_step(\"".$_[0]."\",$_[1],\"".$_[2]."\",\"".$_[3]."\")");

	if($cancelled!=0)
	{
        	Debug::trace_out "    cancelled flag set, exiting immediately";
		return 1;
	}

	my $oprfile=$_[0];
	my $oprstep=$_[1];
	my $opr;	
	my @oprparams;
	my @oprsteplist;
	my $oprdata1=$_[2];
	my $oprdata2=$_[3];

	%opr=read_opr_file($_[0]);
	if(%opr=undef){return 1;}
	# validate we got everything we need from that operation file.
	if($opr{'name'} eq '')
	{
                Debug::error_out('[Operation::one_step] could not find a command in operation file \"'.$_[0].'\"');
		cancel_any_active; return 1;
	}

	# if the current step of the operation is past the end of the list,
	# we're done.
	if(($oprstep+1)>scalar(@{$opr{'steplist'}}))
	{
		Debug::trace_out('[Operation::one_step] current step is past the number of steps in this operation');
		Debug::trace_out('[Operation::one_step] looks like this operation completed, wrapping it up');
		cancel_any_active; return 1;
	}

	# $t will contain the track that execute wants to deliver
	my $t=execute($opr{'name'},\@{$opr{'params'}},\@{$opr{'steplist'}},$oprstep,$oprdata1,$oprdata2);

	# if $t is null, something bad happen, we'll cancel.
	if($t eq '')
	{
		Debug::trace_out('[Operation::execute] did not provide a track, cancelling operation');
		cancel_any_active; return 1;
	}

	# advance operation step
	$oprstep++;
	DataMoving::set_rkey('current_operation_step',$oprstep);

	# and deliver track
 	my $th=md5_hex($t);
 	DataMoving::append_to_list('history',$th);
        # Update play count
        my %t2=DataMoving::get_metadata($th);
        if(%t2!=undef)
      	{
              	$t2{'c'}++;
               	DataMoving::set_metadata($th,\%t2);
        }
        # Deliver it
        DeliverTrack::now_play($t,'',0);

	# DeliverTrack shouldn't return unless there is a serious problem.
	# Probably makes sense to cancel this operation in that case.
	cancel_any_active; return 1;
}


sub duration
{
        Debug::trace_out "*** Operation::duration(\"$_[0]\",\"$_[1]\",\"$_[2]\",\"$_[3]\",\"$_[4]\",\"$_[5]\")";

        $in_which=$_[0];
        @in_params=@{$_[1]};
        @in_list=@{$_[2]};
        $in_step=$_[3];
        $in_data1=$_[4];
        $in_data2=$_[5];

        if($in_which eq 'playall')
        {
                Debug::trace_out("    playall: getting duration for step $in_step: \"$in_list[$in_step]\"");
		my %m=MetadataProcess($in_list[$in_step]);
		if($m!=undef){return $m{'l'}};
        }

	return 240;
}


sub execute
{
        Debug::trace_out "*** Operation::execute(\"$_[0]\",\"$_[1]\",\"$_[2]\",\"$_[3]\",\"$_[4]\",\"$_[5]\")";

	$in_which=$_[0];
	@in_params=@{$_[1]};
	@in_list=@{$_[2]};
	$in_step=$_[3];
	$in_data1=$_[4];
	$in_data2=$_[5];

	if($in_which eq 'playall')
	{
		Debug::trace_out("    playall: playing \"$in_list[$in_step]\"");
		return $in_list[$in_step];
	}
}


sub cancel_any_active
{
	if($cancelled==1){
        	Debug::trace_out('*** Operation::cancel_any_active - already cancelled');
		return;
	}
        Debug::trace_out('*** Operation::cancel_any_active');

	my $operation=DataMoving::get_rkey('current_operation');

	DataMoving::set_rkey('current_operation_file','');
	DataMoving::set_rkey('current_operation','');
	DataMoving::set_rkey('current_operation_step','');
	DataMoving::set_rkey('current_operation_data1','');
	DataMoving::set_rkey('current_operation_data2','');

	$cancelled=1;

	if($operation ne "")
	{
		Debug::debug_out("[Operation::cancel_any_active] active operation \".$operation.\" cancelled");
	}else{
		Debug::debug_out('[Operation::cancel_any_active] there was not an active operation to cancel');
	}
}


sub process_any_active
{
        Debug::trace_out('*** Operation::process_any_active');

	if($cancelled!=0)
	{
        	Debug::trace_out('    cancelled flag set, exiting immediately');
		return 1;
	}

        if($channel eq '')
        {
                Debug::error_out('[Operation::process_any_active] $channel is null.');
                $channel='a jockeycall channel';
        }

        my $operation=DataMoving::get_rkey('current_operation');
	return if($operation eq '');

	$operation_file=DataMoving::get_rkey('current_operation_file');
	$operation_step=DataMoving::get_rkey('current_operation_step');
	$operation_data1=DataMoving::get_rkey('current_operation_data1');
	$operation_data2=DataMoving::get_rkey('current_operation_data2');

	one_step($operation_file,$operation_step,$operation_data1,$operation_data2);
	# one_step shouldn't return, it should deliver a track.
	# if it does return, something bad happened, we'll cancel it.

	Debug::error_out('[Operation::process_any_active] one_step() could not deliver a track, cancelling');
	cancel_any_active;
}

1;
