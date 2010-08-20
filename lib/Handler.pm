package Handler;

# process the fetched response for the crawler:
# * store the download in the database,
# * store the response content in the fs,
# * parse the response content to generate more downloads (eg. story urls from a feed download)
use strict;
use warnings;

# MODULES

use Data::Dumper;
use Date::Parse;
use DateTime;
use Encode;

use FindBin;
use IO::Compress::Gzip;
use URI::Split;
use Switch;

use Carp;
use Perl6::Say;
use List::Util qw (max maxstr);
use HTML::LinkExtractor;

use URI::URL;
use Digest::MurmurHash;
use URI::Escape;
use File::Path;

# CONSTANTS

# max number of pages the handler will download for a single story
use constant MAX_PAGES => 10;
# STATICS

my $_feed_media_ids     = {};
my $_added_xml_enc_path = 0;

# METHODS

sub new
{
    my ( $class, $engine ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->engine( $engine );
    return $self;
}

# chop out the content if we don't allow the content type
sub _restrict_content_type
{
    my ( $self, $response , $content_type) = @_;

##TODO not using content type here nedd to change it in fetcher it selfwhile getting the head
    if ( $response->content_type =~ m~text|html|xml|rss|atom~i )
    {
        return;
    }

    #if ($response->decoded_content =~ m~<html|<xml|<rss|<atom~i) {
    #    return;
    #}

    print "unsupported content type: " . $response->content_type . "\n";
    $response->content( '(unsupported content type)' );
}

sub standardize_url
{
        my ( $url ) = @_;
        $url = URI->new($url)->canonical;
        
        if (!$url->can('host'))
        {
        	return "";
        }
        my $new_url = $url->scheme()."://".$url->host().":".$url->port().$url->path();
        if (defined ($url->query()))
        {
                $new_url = $new_url.'?'.$url->query();
        }
        $url = URI->new($new_url);
        my $encoded_url = uri_escape($url);
        return ($encoded_url) ;
}

# call get_page_urls from the pager module for the download's feed
sub _call_pager
{
    my ( $self, $download, $response ) = @_;

    if ( $download->{ sequence } > $download->{ _depth_of_search } )
    {
        print "reached max pages (" . MAX_PAGES . ") for url " . $download->{ url } . "\n";
        return;
    }

    my $dbs = $self->engine->dbs;

    if ( $dbs->query( "SELECT * from downloads where parent = ? ", $download->{ downloads_id } )->hash )
    {
        print "story already paged for url " . $download->{ url } . "\n";
        return;
    }

    my $validate_url = sub { !$dbs->query( "select 1 from downloads where url = ?", $_[ 0 ] ) };

    my $content = $response->content;
    my $base = $response->base;
    my @links = ();

    my $LX = new HTML::LinkExtractor;
    $LX->parse(\$content);
    $LX->links();
    my @tags = @{$LX->links()};
    
    for (my $i=0;$i < @tags;$i++){ if (defined $tags[$i]->{href}) {push(@links,$tags[$i]->{href}); } }
    @links = map { $_ = url($_, $base)->abs; } @links;
    @links = map { $_ = standardize_url($_) } @links;
    my %hash_links   = map { $_, 1 } @links;
    my @unique_links = keys %hash_links;
    
    #print "Unique urls parsed: \n",join("\n",@unique_links) ,"\n";
    my $j=0;
    $download ->{ childs } = int(@unique_links);
    my $request_check = $dbs->find_by_id('requests',$download->{ request_id });
    if ($request_check->{ status } ne "dequeued")
    {
	    foreach $j (@unique_links)
	    {
			     	$dbs->create(
			            'downloads',
			            {
			                parent        => $download->{ downloads_id },
			                request_id	  => $download->{ request_id },
			                url           => $j,
			                host          => lc( ( URI::Split::uri_split( uri_unescape($j) ) )[ 1 ] ),
			                type          => 'archival_only',
			                sequence      => $download->{ sequence } + 1,
			                state         => 'pending',
			                download_time => 'now()',
			                extracted     => 'f'
			            }
			        );
	    }
	    $download ->{ extracted } = 't';
	    $download->{ state } = 'success';
	    $self->update_parent($download);
	    $dbs->update_by_id( "downloads", $download->{ downloads_id }, $download );	
    }
    else
    {
    	print STDERR "request is dequeued so skipping \n";
    }
    
                   
=comment
    my $parent_link = $self->$dbs->find_by_id( 'downloads', $download->{ downloads_id } );
    if ( my $next_page_url =
        MediaWords::Crawler::Pager->get_next_page_url( $validate_url, $download->{ url }, $response->decoded_content ) )
    {

        print "next page: $next_page_url\nprev page: " . $download->{ url } . "\n";

        $dbs->create(
            'downloads',
            {
                parent        => $download->{ downloads_id },
                url           => $next_page_url,
                host          => lc( ( URI::Split::uri_split( $next_page_url ) )[ 1 ] ),
                type          => 'content',
                sequence      => $download->{ sequence } + 1,
                state         => 'pending',
                priority      => $download->{ priority } + 1,
                download_time => 'now()',
                extracted     => 'f'
            }
        );
    }
=cut

}

# call the content module to parse the text from the html and add pending downloads
# for any additional content
sub _process_content
{
    my ( $self, $download, $response ) = @_;
    $self->_call_pager( $download, $response );

    #MediaWords::Crawler::Parser->get_and_append_story_text
    #($self->engine->db, $download->feeds_id->parser_module,
    #$download->stories_id, $response->decoded_content);
}

sub handle_response
{
    my ( $self, $download, $cond, $response, $head ) = @_;

    #say STDERR $cond ;
    #say STDERR "fetcher " . $self->engine->fetcher_number . " handle response: " . $download->{url};

    my $dbs = $self->engine->dbs;

    if ( !$response->is_success )
    {
        $dbs->query(
            "update downloads set state = 'error', error_message = ? where downloads_id = ?",
            encode( 'utf-8', $response->status_line ),
            $download->{ downloads_id }
        );
        return;
    }

    # say STDERR "fetcher " . $self->engine->fetcher_number . " starting restrict content type";

    $self->_restrict_content_type( $response ,$download->{ allowed_content } );


    # say STDERR "fetcher " . $self->engine->fetcher_number . " starting reset";
    # may need to reset download url to the last redirect url
    
    #TODO decide whether to reset the download url to last requested or not
    #presently not setting it back
    #$download->{ url } = ( $response->request->url );
    #$dbs->update_by_id( "downloads", $download->{ downloads_id }, $download );

    # say STDERR "switching on download type " . $download->{type};
    
    switch ( $cond )
    {
        case ('cond1')
        {
        	if ( $download->{ sequence } > $download->{ depth_of_search } )
    			{
			        print "reached max pages (" . MAX_PAGES . ") for url " . $download->{ url } . "from the request with request_id ".$download->{ request_id }."\n";
			        return;
    			}
    		else
    			{
    				$download->{ download_id_of_old_copy } = $response -> { downloads_id } ;
		            $download->{ location } = $head->request->url;
		            #path is null $$ download success  implies --> content not modified 
		            #$download->{ path } = $response->{ path };
		            $download->{ mm_hash_location } = Digest::MurmurHash::murmur_hash($head->request->url);
		            
		            $self->update_parent($download);
		            
		            $download->{ state } = 'success';
		            $dbs->update_by_id( "downloads", $download->{ downloads_id }, $download );
    			}
            
        }
        case ('cond2')
        {
        	store_content( $dbs, $download, \$response->decoded_content );
        	#path, is set and state updated to success
        	$download->{ download_id_of_old_copy } = $response -> { downloads_id } ;
            $download->{ location } = $response->request->url;
            $download->{ mm_hash_location } = Digest::MurmurHash::murmur_hash($response->request->url);
            $dbs->update_by_id( "downloads", $download->{ downloads_id }, $download );
            $self->_process_content( $download, $response );
        }
        case ('cond3')
        {
        	#no need to download same location present in DB and considered as fresh copy
        	#removing row
        	$self->update_parent($download);
    		
        	$dbs->query("DELETE FROM downloads WHERE downloads_id=?",$download->{ downloads_id });
        }
        case ('cond4')
        {
        	store_content( $dbs, $download, \$response->decoded_content );
        	$download->{ location } = $response->request->url;
        	$download->{ mm_hash_location } = Digest::MurmurHash::murmur_hash($response->request->url);
        	$dbs->update_by_id( "downloads", $download->{ downloads_id }, $download );
            $self->_process_content( $download, $response );
        }
        case ('cond5')
        {
        	$response->content( '(unsupported content type)' );
        	$download->{ error_message } = "unsupported content type";
        	$self->update_parent($download);
        	$dbs->update_by_id( "downloads", $download->{ downloads_id }, $download );
        }
        else
        {
            die "Unknown download type " . $download->{ type }, "\n";
        }
        
    }
}

sub update_parent
{
	my ( $self,$download ) = @_ ;
	my $dbs = $self->engine->dbs;
	if($download->{ parent } != 0)
	{
		my $parent = $dbs->find_by_id('downloads',$download->{ parent });
		#print STDERR "**********************",$parent -> { childs };
	    $parent -> { childs } = $parent -> { childs } - 1;
	    $dbs->update_by_id( "downloads",$parent->{ downloads_id }, $parent );
	    if( $parent -> { childs } == 0 )
	    {
	    	update_parent($self,$parent);
	    }
	}
	else
	{
		#notify seeds that their downloads are finished
		my $download_queue_row = $dbs->find_by_id("downloads_queue",$download->{ download_id });
		$download_queue_row->{ status } = "done";
		$dbs->update_by_id("downloads_queue",$download_queue_row->{ url_id },$download_queue_row);
		
	}
}

# get the parent of this download
sub get_parent
{
    my ( $db, $download ) = @_;

    if ( !$download->{ parent } )
    {
        return undef;
    }

    return $db->query( "select * from downloads where downloads_id = ?", $download->{ parent } )->hash;
}

# store the download content in the file system
sub store_content
{
    my ( $db, $download, $content_ref ) = @_;

    
    my $feed = $db->query( "select * from downloads where downloads_id = ?", $download->{ downloads_id } )->hash;

    my $t = DateTime->now;

    my $config = CConfig->get_config;
    my $data_dir = $config->{ mediawords }->{ data_content_dir } || $config->{ mediawords }->{ data_dir };

    my @path = (
        'content',
        sprintf( "%04d", $t->year ),
        sprintf( "%02d", $t->month ),
        sprintf( "%02d", $t->day ),
        sprintf( "%02d", $t->hour ),
        sprintf( "%02d", $t->minute )
    );
    for ( my $p = get_parent( $db, $download ) ; $p ; $p = get_parent( $db, $p ) )
    {
        push( @path, $p->{ downloads_id } );
    }

    my $rel_path = join( '/', @path );
    my $abs_path = "$data_dir/$rel_path";

    mkpath( $abs_path );

    my $rel_file = "$rel_path/" . $download->{ downloads_id } . ".gz";
    my $abs_file = "$data_dir/$rel_file";

    my $encoded_content = Encode::encode( 'utf-8', $$content_ref );

    # print STDERR "file path '$abs_file'\n";

    if ( !( IO::Compress::Gzip::gzip \$encoded_content => $abs_file ) )
    {
        my $error = "Unable to gzip and store content: $IO::Compress::Gzip::GzipError";
        $db->query( "update downloads set state = ?, error_message = ? where downloads_id = ?",
            'error', $error, $download->{ downloads_id } );
    }
    else
    {
        $db->query( "update downloads set state = ?, path = ? where downloads_id = ?",
            'success', $rel_file, $download->{ downloads_id } );
    }
}
# calling engine
sub engine
{
    if ( $_[ 1 ] )
    {
        $_[ 0 ]->{ engine } = $_[ 1 ];
    }

    return $_[ 0 ]->{ engine };
}

1;
