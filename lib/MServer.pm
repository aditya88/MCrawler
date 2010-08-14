package MServer;

use warnings;
use strict;
use Data::Dumper;
use base qw(Net::Server::PreFork);
use Switch;
use Perl6::Say;

sub new{
	my ( $class,$port ) = @_;
	my $self = {};
    bless( $self, $class );
    $self->reconnect_db();
	return $self;
}

sub make_request{
	my ($self,$client_id) = @_;
	print STDERR " $client_id is the client id that requested new download \n";
	my $dbs = $self->dbs;
	my $row = $dbs->create(
					            'requests',
					            {
					                client_id     => $client_id
					            }
					            );
	
	$dbs->commit();
	return $row->{ request_id };
=comment
	$dbs->query("INSERT INTO requests (client_id) VALUES (?)",$client_id);
	my $last_insert_id = $dbs->last_insert_id(undef,undef,'requests',undef);
	my $row = $dbs->find_by_id("requests",$last_insert_id)->hash;
	return $row->{ request_id };
=cut

}

sub handle_queue{
	my ($self,$client_id,$request_id,@urls) = @_;
	my $dbs = $self->dbs;
#	print STDERR @urls;
#	shift(@urls);
	if($self->validate($client_id,$request_id))
	{
	while(scalar(@urls) != 0) {
		my $url = shift(@urls);
#		print scalar(@urls);
		$dbs->query("INSERT INTO downloads_queue (request_id,url,status) VALUES (?,?,'new')",$request_id,$url);
#   	print STDERR "inserted ",$url,"\n";
   		$dbs->commit();
	}	
	}
	else{
#TODO some error
	}
}

sub validate{
	
	my($self,$client_id,$request_id)=@_;
	my $dbs = $self->dbs;
	my $result = $dbs->query("SELECT client_id FROM requests WHERE request_id=?",$request_id)->hash;
	
	print Dumper($result),"in validate";
	if ($result->{ client_id } == $client_id){
		return 1;
	}
	else{
		return 0;
	}
}
sub get_request{
	my($self,$request_id)=@_;
	my $dbs = $self->dbs;
	return $dbs->query("SELECT 1 FROM requests WHERE request_id =?",$request_id)->hash();
}
sub make_settings{
	my($self,$client_id,$request_id,$case,@tokens) = @_;
	if($self->validate($client_id,$request_id)){
		
		my $dbs = $self->dbs;
		#my $request = $self->get_request($request_id);
		my $request = $dbs->find_by_id( 'requests', $request_id );
		#my $request = $dbs->query("SELECT 1 FROM requests WHERE request_id =?",$request_id)->hash();
		#my $hash = $request->hash();
		 
        
        if ( !$request ) 
        { 
        	die( "error" ); 
        }
        
        switch ($case)
        {
        	case "commit_request"
        	{
	        	print STDERR "Commit request \n";
	        	$request->{ status } = "ready";	
            }
            case "check_status"
        	{
	        	print STDERR "Creating a view for present status of request";
	        	##TODO to be fixed hard coding
	        	my $temp_view = "view_".$client_id."_".$request_id;
	        	my $dbh;
	        	if ($dbh=$dbs->query("CREATE VIEW ".$temp_view." AS SELECT * FROM downloads WHERE request_id=?",$request_id))
	        	{
	        		#new view created 
	        		my $grant_permission = $dbs->query("GRANT SELECT ON ".$temp_view." TO client_".$client_id);
	        		
	        	}
	        	print STDOUT "please check your request status on $temp_view table\n";
	        	
	        	my @urls_of_requests = $dbs->query("SELECT * FROM downloads_queue WHERE request_id=?",$request_id)->hashes();
	        	my @url_done_statuses = $dbs->query("SELECT * FROM downloads_queue WHERE request_id=? AND status='done'",$request_id)->hashes();
	        	
	        	print STDOUT "Out of @urls_of_requests urls,@url_done_statuses are completed and remaining are in processing";
        
        	}
        	case "dequeue_request"
	        {
	        	print STDERR "Dequeueing the request($request_id) of $client_id";
	        	#revoke permissions and delete request
	        	my $temp_view = "view_".$client_id."_".$request_id;
	        	my $client = "client_".$client_id;
	        	$dbs->query("REVOKE ALL PRIVILEGES ON ".$temp_view." FROM ".$client);
	        	$dbs->query("DROP VIEW ".$temp_view);
	        	$dbs->query("DELETE FROM requests WHERE request_id=?",$request_id);
	        	$dbs->query("DELETE FROM downloads_queue WHERE request_id=?",$request_id);
	        	$dbs->query("DELETE FROM downloads WHERE request_id=?",$request_id);
	        	
	        }
	        else
	        {
	        	$request->{ $case } = shift(@tokens);
	        }
        }
        print STDERR Dumper($request); 
        $dbs->update_by_id( "requests", $request->{ request_id }, $request );
        $dbs->commit();
	}
}

sub process_request {
	 my $self = shift;
	 #print STDOUT "you are connected server";
	 while(my $msg = <STDIN>)
	 {
	 	say STDERR $msg;
	 	my @tokens = split(/\s+/,$msg);
	 	my $client_id = shift(@tokens);
	 	my $switch=shift(@tokens);
	 	$switch=~s/\n//g;
	 	if($switch eq "request"){
	 		print STDERR "new request \n";
 			my $new_request_id = $self->make_request($client_id);
 			print STDERR "your request id is $new_request_id \n";
 			print STDOUT "you($client_id) made new request $new_request_id \n";	 		
	 	}
	 	else{
	 		my $request_id = $switch;
	 		my $case = shift(@tokens);
	 		switch($case){
		 		case "queue"
		 		{
		 			$self->handle_queue($client_id,$request_id,@tokens);
		 		}
		 		case ["downloads_type","depth_of_search","refresh_rate","allowed_content","commit_request","check_status","dequeue_request"]
		 		{
		 			#print STDERR "switch done";
					$self->make_settings($client_id,$request_id,$case,@tokens);		 			
		 		}
	 		}	
	 	}
	 }
	 
=comment
        my $self = shift;
        while (<STDIN>) {
            s/\r?\n$//;
            print "You said '$_'\r\n", <STDIN>; # basic echo
            last if /quit/i;
        }
=cut
    }
    
sub post_accept_hook()
{
}

sub dbs
{
    my ( $self, $dbs ) = @_;

    if ( $dbs )
    {
        die( "use $self->reconnect_db to connect to db" );
    }

    defined( $self->{ dbs } ) || die "no database";

    return $self->{ dbs };
}

sub reconnect_db
{
    my ( $self ) = @_;

    if ( $self->{ dbs } )
    {
        $self->dbs->disconnect;
    }
    $self->{ dbs } = DB->connect_to_db;
    $self->dbs->dbh->{ AutoCommit } = 0;
}

1;