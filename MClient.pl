#!/usr/bin/perl
use constant SERVER_PORT => 6666;
use constant CLIENT_ID => 8989;
use strict;
use warnings;
use Switch;
use IO::Socket::INET;
use threads;
use threads::shared;
use Perl6::Say;

# Create a new socket

my $MySocket;
my $def_msg="Enter message to send to server : ";
my $server_reply="";
my $inbox : shared ="";

sub connect_server{
my $MySocket=new IO::Socket::INET->new(	PeerPort=>SERVER_PORT,
										Proto=>'tcp',
										PeerAddr=>'localhost'
									   );
die "Could not create socket: $!\n" unless $MySocket;
return $MySocket;
}

sub send_to_server{
	my $msg = CLIENT_ID." ".$_[0]."\n";
	#print STDERR $msg;
		if(send($MySocket,$msg,0))
		{
			return "sent $_[0] ";
		}
		else
		{
			return "error in sending message";
		}
}

sub handle_queue{
	if(@_ != 0){
	my $request_id = shift(@_);
	my $input = join(" ",@_);
	return send_to_server($request_id." queue ".$input);
	}
}

sub load_file_and_queue{
	my $request_id = shift(@_);
	my $file = shift(@_);
	my $data = " ";
	if(open LOAD_FILE, "<$file")
	{
		while (<LOAD_FILE>) 
		{
			my $url= $_;
			chomp($url);
			$data = $data." ".$url;
		}
#		print ("queue".$data);
		return send_to_server($request_id." queue ".$data);
	}
	else 
	{
		return "Could not open file '$file '. $!" ;
	}
}

sub listen_server{
		while ($server_reply = <$MySocket>)
			{
			if($server_reply ne '')
				{
				$inbox = $inbox."\n".$server_reply;
				}
			}	
}

sub start_client{
	print "client started ";
	$MySocket = connect_server();
	print "connected to server\n";
	my $thr = threads->new(\&listen_server);
	print "enter 'help' for help \n";
		while (1)
			{	print "\nSend message to server : ";
				my $input = <STDIN>;
				$input =~s/^\s+|\s+$|\n//g;
				my @tokens = split(/\s+/,$input);
				#print STDERR $tokens[0];
				#my @case_hash = {"downloads_type","depth_of_search","refresh_rate","allowed_content","user_agent","commit_request"};
				switch ($tokens[0])
				{
					my $token = shift(@tokens);
					case "help"{
						            print " \n The follwing are the commands:\n new_request --> initializing a new request \n check_inbox --> check messages from server for any new request_id\n queue_url <request_id><space><url> --> queueing a single url\n queue_file <request_id><space><file_location> --> queueing a file with urls\n allowed_content <request_id><space><value> --> setting content type default - html|text\n depth_of_search <request_id><space><value> --> setting depth of search default - 3 \n refresh_rate <request_id><space><value> --> setting refresh rate default - 24*24*3600\n user_agent <request_id><space><value> --> setting user_agent default -\n commit_request <request_id> --> starts the defined request\n dequeue_request -->dequeue request removes all data regarding that request from database\n check_status -->gives present status of the request ";
					}					
					case "new_request"{
									print send_to_server("request");
					}
					case "queue_url" {
									print handle_queue(@tokens);  
					}
					case "queue_file"{
									print load_file_and_queue(@tokens);
					}
					case["downloads_type","depth_of_search","refresh_rate","allowed_content","user_agent","check_status","commit_request","dequeue_request"]
					{
						my $request_id=shift(@tokens);
						if (defined($request_id)) {
									print send_to_server($request_id." ".$token." ".join(" ",@tokens) );	
									}
					    else{
					    			print "please enter with request_id\ncheck syntax with help command";
					    			}
									
					}
					case "check_inbox"{
									print "\n messages received from server are: ".$inbox;
									$inbox = "";
					}
					else{
						print "wrong input \ntype 'help' for help\n";
					}
				}

			}
				
}

start_client();
