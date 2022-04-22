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

# Channel, main should set this
our $channel;

# I wrote a note about why this is here in OOB.pm.  Same deal.
sub set_channel { $channel=$_[0]; }


sub kickoff
{
        Debug::trace_out "*** kickoff(\"".$_[0]."\")";

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


sub one_step
{
        Debug::trace_out "*** one_step(\"".$_[0]."\",$_[1],\"".$_[2]."\",\"".$_[3]."\")";

	if($cancelled!=0)
	{
        	Debug::trace_out "cancelled flag set, exiting immediately";
		return 1;
	}

	my $oprfile=$_[0];
	my $oprstep=$_[1];
	my $opr;	
	my @oprparams;
	my @oprsteplist;
	my $oprdata1=$_[2];
	my $oprdata2=$_[3];

        # file doesn't exist? report error and return.
        if(! -e $_[0])
        {
                Debug::error_out "one_step(): operation file \"".$_[0]."\" doesn't exist.";
		cancel_any_active;
                return 1;
        }

        open(my $oprfilehandle,'<',$oprfile); ##or Concurrency::fail "open of $oprfilehandle failed";
        while(<$oprfilehandle>)
        {
                my $line=$_;
                $line=~s/^\s+|\s+$//g;

                next if($line eq ''); # skip blank lines
                next if($line =~ /^\s*#/); # skip lines beginning with # - comments
	
		# If $current_operation is null then we're looking for a line
		# that has the operation command
		if(!$opr)
		{
			@oprparams=split(/ /,$line);
			$opr=shift @oprparams;
			if(!(any{/$opr/}@valid_operation_names))
			{
                		Debug::error_out "one_step(): the command \"".$opr."\" in operation file \"".$_[0]."\" is not recognized.";
				cancel_any_active;
				return 1;
			}
			next;
		}

		# If $current_operation is not null then we're looking at steps
		# and we can go ahead and shove them into the array.
		push(@oprsteplist,$line);
        }
        close($oprfilehandle);

	# validate we got everything we need from that operation file.
	if(!$opr)
	{
                Debug::error_out "one_step(): couldn't find a command in operation file \"".$_[0]."\".";
		cancel_any_active;
		return 1;
	}

	operation_execute($opr,@oprparams,@oprsteplist,$oprstep,$oprdata1,$oprdata2);
	# operation_execute shouldn't return, it should deliver a track.
	# it is responsible for updating operation vars.
	# if it does, something bad happened.
}


sub operation_execute
{
        Debug::trace_out "*** operation_execute( ... )";
	if($opr eq 'playall')
	{
		
	}

}


sub cancel_any_active
{
        Debug::trace_out "*** cancel_any_active";

	my $operation=DataMoving::get_rkey("current_operation");

	DataMoving::set_rkey("current_operation_file",'');
	DataMoving::set_rkey("current_operation",'');
	DataMoving::set_rkey("current_operation_step",'');
	DataMoving::set_rkey("current_operation_data1",'');
	DataMoving::set_rkey("current_operation_data2",'');

	$cancelled=1;

	if($operation ne "")
	{
		Debug::debug_out "active operation \".$operation.\" cancelled";
	}else{
		Debug::debug_out "there wasn't an active operation to cancel";
	}
}


sub process_any_active
{
        Debug::trace_out "*** process_any_active";

	if($cancelled!=0)
	{
        	Debug::trace_out "cancelled flag set, exiting immediately";
		return 1;
	}

        if($channel eq '')
        {
                Debug::error_out '$channel is null.';
                $channel='a jockeycall channel';
        }

        my $operation=DataMoving::get_rkey("current_operation");
	return if($operation eq "");

	$operation_file=DataMoving::get_rkey("current_operation_file");
	$operation_step=DataMoving::get_rkey("current_operation_step");
	$operation_data1=DataMoving::get_rkey("current_operation_data1");
	$operation_data2=DataMoving::get_rkey("current_operation_data2");

	one_step($operation_file,$operation_step,$operation_data1,$operation_data2);
	# one_step shouldn't return, it should deliver a track.
	# if it does return, something bad happened.

	Debug::error_out "process_any_active(): one_step() couldn't deliver a track.";
	cancel_any_active;
}

1;
