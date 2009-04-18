package Yggdrasil::Storage::Engine::SQLite;

use strict;
use warnings;

use base 'Yggdrasil::Storage::Engine::Shared::SQL';

use DBI;

our %TYPEMAP = (
    SERIAL   => 'INTEGER PRIMARY KEY',
    PASSWORD => 'VARCHAR(255)',
    );

sub new {
    my $class = shift;
    my $self  = {};
    my %data  = @_;

    bless $self, $class;

    my $status = $self->get_status();

    $data{db} ||= 'yggdrasil';
    $data{path} ||= '/tmp';

    my $path = join('/', $data{path}, $data{db});
    $self->{dbh} = DBI->connect( "dbi:SQLite:dbname=$path", "", "" );

    return $self;
}

sub yggdrasil_is_empty {
    my $self = shift;

    for my $struct ($self->_list_structures()) {
	return 0 if $struct !~ /Storage_/;
    }
    return 1;
}

sub _structure_exists {
    my $self = shift;
    my $structure = shift;

    for my $table ( $self->_list_structures( $structure ) ) {
	return $structure if $table eq $structure;
    }
    return 0;
}

sub _list_structures {
    my $self = shift;
    my $structure = shift;

    my $string = "SELECT name FROM sqlite_master WHERE type = 'table'";
    $string .= " AND name LIKE '%" . $structure . "%'" if $structure;

    my( $e ) = $self->_sql( $string );

    my @tables;
    for my $row ( @$e ) {
	for my $table ( values %$row ) {
	    push @tables, $table;
	}
    }
    return @tables;
}

sub _map_type {
    my $self = shift;
    my $type = shift;

    return $TYPEMAP{$type} || $type;
}

sub _null_comparison_operator {
    return 'is';
}

sub _engine_requires_serial_as_key {
    return 1;
}

sub _convert_time {
    my $self = shift;
    my $time = shift;

    return $time unless defined $time;

    if( $self->_isepoch($time) ) {
	return "datetime($time, 'unixepoch', 'localtime')";
    }
    return $time;
}

sub _time_as_epoch {
    my $self = shift;
    my $time = shift;

    return "strftime('%s','$time')"; 
}

1;
