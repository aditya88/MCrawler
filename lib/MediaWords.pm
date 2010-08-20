package MediaWords;

# local subclass of DBIx::Simple with some modification for use in media cloud code

use strict;

use Carp;
use IPC::Run3;

use CConfig;
use DB;

use Data::Page;
use Perl6::Say;
use Data::Dumper;
use base qw(DBIx::Simple);
# STATICS

# cache of table primary key columns
my $_primary_key_columns = {};

# METHODS

sub new
{
    my $proto = shift;
    my $class = ref( $proto ) || $proto;

    my $self = $class->SUPER::new();

    bless( $self, $class );

    return $self;
}

sub query
{
    my $self = shift @_;

    my $ret = $self->SUPER::query( @_ );

    return $ret;

}

sub query_continue_on_error
{
    my $self = shift @_;

    my $ret = $self->SUPER::query( @_ );

    return $ret;
}

sub query_only_warn_on_error
{
    my $self = shift @_;

    my $ret = $self->SUPER::query( @_ );

    warn "Problem executing DBIx::simple->query(" . scalar( join ",", @_ ) . ") :" . $self->error
      unless $ret;
    return $ret;
}

# get the primary key column for the table
sub primary_key_column
{
    my ( $self, $table ) = @_;

    if ( my $id_col = $_primary_key_columns->{ $table } )
    {
        return $id_col;
    }

    my ( $id_col ) = $self->dbh->primary_key( undef, undef, $table );

    $_primary_key_columns->{ $table } = $id_col;

    return $id_col;
}

# do an id lookup on the table and return a single row match if found
sub find_by_id
{
    my ( $self, $table, $id ) = @_;

    my $id_col = $self->primary_key_column( $table );

    confess "undefined primary key column for table '$table'" unless defined( $id_col );

    return $self->query( "select * from $table where $id_col = ?", $id )->hash;
}

# update the row in the table with the given id
# ignore any fields that start with '_'
sub update_by_id
{
    my ( $self, $table, $id, $hash ) = @_;

    delete( $hash->{ submit } );

    my $id_col = $self->primary_key_column( $table );

    my $hidden_values = {};
    for my $k ( grep( /^_/, keys( %{ $hash } ) ) )
    {
        $hidden_values->{ $k } = $hash->{ $k };
        delete( $hash->{ $k } );
    }

    my $r = $self->update( $table, $hash, { $id_col => $id } );

    while ( my ( $k, $v ) = each( %{ $hidden_values } ) )
    {
        $hash->{ $k } = $v;
    }
}

# delete the row in the table with the given id
sub delete_by_id
{
    my ( $self, $table, $id ) = @_;

    my $id_col = $self->primary_key_column( $table );

    return $self->query( "delete from $table where $id_col = ?", $id );
}

# insert a row into the database for the given table with the given hash values and return the created row as a hash

sub create
{
    my ( $self, $table, $hash ) = @_;

    delete( $hash->{ submit } );

    $self->insert( $table, $hash );

    my $id;

    eval {
        $id = $self->last_insert_id( undef, undef, $table, undef );

        confess "Could not get last id inserted" if ( !defined( $id ) );
    };

    confess "Error getting last_insert_id $@" if ( $@ );

    my $ret = $self->find_by_id( $table, $id );

    confess "could not find new id '$id' in table '$table' " unless ( $ret );

    return $ret;
}

# run create for the given table, retrieving the given fields from the request object
sub create_from_request
{
    my ( $self, $table, $request, $fields ) = @_;

    my $hash;
    for my $field ( @{ $fields } )
    {
        $hash->{ $field } = $request->param( $field );
    }

    return $self->create( $table, $hash );
}

# select a single row from the database matching the hash or insert
# a row with the hash values and return the inserted row as a hash
sub find_or_create
{
    my ( $self, $table, $hash ) = @_;

    delete( $hash->{ submit } );

    if ( my $row = $self->select( $table, '*', $hash )->hash )
    {
        return $row;
    }
    else
    {
        return $self->create( $table, $hash );
    }

}

# execute the query and return a list of pages hashes
sub query_paged_hashes
{
    my ( $self, $query, $page, $rows_per_page ) = @_;

    $page ||= 1;

    my $offset = ( $page - 1 ) * $rows_per_page;

    $query .= " limit ( $rows_per_page + 1 ) offset $offset";

    my $rs = $self->query( $query );

    my $list = [];
    my $i    = 0;
    my $hash;
    while ( ( $hash = $rs->hash ) && ( $i++ < $rows_per_page ) )
    {
        push( @{ $list }, $hash );
    }

    my $max = $offset + $i;
    if ( $hash )
    {
        $max++;
    }

    my $pager = Data::Page->new( $max, $rows_per_page, $page );

    return ( $list, $pager );

}

# executes the supplied subroutine inside a transaction
sub transaction
{
    my ( $self, $tsub, @tsub_args ) = @_;

    $self->query( 'START TRANSACTION' );

    eval {
        if ( $tsub->( @tsub_args ) )
        {
            $self->query( 'COMMIT' );
        }
        else
        {
            $self->query( 'ROLLBACK' );
        }
    };

    if ( my $x = $@ )
    {
        $self->query( 'ROLLBACK' );

        # TODO: This obliterates any stack trace that exists.
        # See <http://stackoverflow.com/questions/971273/perl-sigdie-eval-and-stack-trace>
        die $x;
    }
}

1;
