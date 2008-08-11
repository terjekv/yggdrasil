package Yggdrasil::Entity::Instance;

use base 'Yggdrasil::Meta';

use strict;
use warnings;

use Carp;

sub new {
  my $class = shift;

  my( $pkg ) = caller();
  my $self = $class->SUPER::new(@_);

  return $self if $pkg ne 'Yggdrasil::Entity::Instance' && $pkg =~ /^Yggdrasil::/;

  # --- do stuff
  my $visual_id = shift;
  $self->{visual_id} = $visual_id;

  my $entity = $self->_extract_entity();
  $self->{_id} = $self->_get_id(); 

  unless ($self->{_id}) { 
      $self->{storage}->store( $entity, fields => { visual_id => $visual_id } );
      $self->{_id} = $self->_get_id();
  }
  
  return $self;
}

sub _get_id {
    my $self = shift;
    my $entity = $self->_extract_entity();
    my $idfetch = $self->{storage}->fetch( $entity =>
					   { return => "id", where => { visual_id => $self->id() } } );
    return $idfetch->[0]->{id};
}

sub get {
  my $class = shift;
  my $visual_id = shift;

  if ($class->exists( $visual_id )) {
      return $class->new( $visual_id );
  } else {
      return undef;
  }
}

sub _define {
  my $self     = shift;
  my $property = shift;

  my( $pkg ) = caller(0);
  if( $property =~ /^_/ && $pkg !~ /^Yggdrasil::/ ) {
    die "You bastard! private properties are not for you!\n";
  }
  my $entity = $self->_extract_entity();
  my $name = join("_", $entity, $property);

  # --- Create Property table
  $self->{storage}->define( $name,
			    fields   => { id    => { type => "INTEGER" },
					  value => { type => "TEXT" } },
			    temporal => 1 );
  
  # --- Add to MetaProperty
  $self->{storage}->store( "MetaProperty", key => "id", fields => { entity => $entity, property => $property } );

  return $property;
}

sub property {
    my $self = shift;
    my ($key, $value) = @_;

    my $storage = $self->{storage};

    my $entity = $self->_extract_entity();
    my $name = join("_", $entity, $key );

    if ($value) {
	$storage->store( $name, key => "id", fields => { id => $self->{_id}, value => $value } );
    }

    return $storage->fetch( $name => { return => "value", where => { id => $self->{_id} } } );
}

sub property_exists {
    confess "Not implemented";
}

sub properties {
    my $class = shift;
    $class =~ s/.*:://;
    
    return $Yggdrasil::STORAGE->properties( $class );
}

sub search {
    my ($class, $key, $value) = @_;
    my $package = $class;
    $class =~ s/.*:://;
    
    my $nodes = $Yggdrasil::STORAGE->search( $class, $key, $value );

    return map { my $new = $package->SUPER::new(); $new->{visual_id} = $_;
		 $new->{_id} = $nodes->{$_}; $new } keys %$nodes;
}

sub link :method {
  my $self     = shift;
  my $instance = shift;

  my $e1 = $self->_extract_entity();
  my $e2 = $instance->_extract_entity();

  my $schema = $self->_get_relation( $e1, $e2 );
  
  # Check to see if the relationship between the entities is defined
  confess "Undefined relation between $e1 / $e2 requested." unless $schema;

  my $e1_side = $self->_relation_side( $schema, $e1 );
  my $e2_side = $self->_relation_side( $schema, $e2 );

  $self->{storage}->store( $schema,
			   key => 'id',
			   fields => { $e1_side => $self->{_id},
				       $e2_side => $instance->{_id} });
}

sub unlink :method {
  my $self     = shift;
  my $instance = shift;
 
  my $e1 = $self->_extract_entity();
  my $e2 = $instance->_extract_entity();
  
  my $storage = $self->{storage};

  my $schema = $storage->fetch( "MetaRelation", => { where => { entity1 => $e1, entity2 => $e2 } });

  my $e1_side = $self->_relation_side( $schema, $e1 );
  my $e2_side = $self->_relation_side( $schema, $e2 );
  

  $storage->expire( $schema, $e1_side => $self->{_id}, $e2_side => $instance->{_id} );
}

sub id {
  my $self = shift;
  
  return $self->{visual_id};
}

sub pathlength {
    my $self = shift;
    return $self->{_pathlength};
}

sub fetch_related {
  my $self = shift;
  my $relative = shift;

  $relative =~ s/^.*:://;
  my $source = $self->_extract_entity();

  my $paths = $self->_fetch_related( $source, $relative );

  my @relations = $self->{storage}->relations();
  my %table_map;
  foreach my $r ( @relations ) {
    my( $e1, $e2, $rel ) = @$r;
    $table_map{ join("_", $e1, $e2) } = [ $rel, $e1 ];
    $table_map{ join("_", $e2, $e1) } = [ $rel, $e1 ];
  }

  my %result;
  for my $path ( @$paths ) {
    print "ZOOM ",  join( " -> ", @$path), "\n";
  
    my @tmp_path = @$path;
    my $node = shift @tmp_path;
    my @ordered;
    foreach my $step ( @tmp_path ) {
       push( @ordered, $table_map{ join("_", $node, $step) }->[0] );
       $node = $step;
     }


    my @where;
    my $first = $ordered[0];
    my $side = $self->_relation_side( $first, $source );
    my $firsttable = $self->_map_table_name( $first );
    push( @where, "$firsttable.$side = $self->{_id} and $firsttable.stop is null" );
    my $prev = $first;
    for( my $i=1; $i<@ordered; $i++ ) {
      my $table = $ordered[$i];

      my $rel = $table_map{ join("_", $table, $prev) };
      
      my $current = $self->_relation_side( $table, $path->[$i] );
      my $next    = $self->_relation_side( $prev, $path->[$i] );
      my $tabname = $self->_map_table_name( $table );
      my $prevtab = $self->_map_table_name( $prev );
      
      push( @where, "$tabname.$current = $prevtab.$next and $tabname.stop is null");
      $prev = $table;
    }
    
    $side = $self->_relation_side( $ordered[-1], $path->[-1] );
    my ($ordtab, $pathtab) = ($self->_map_table_name( $ordered[-1] ), $self->_map_table_name( $path->[-1] ));
    push(@where, "$ordtab.$side = $pathtab.id" );

    my $pathtable  = $self->_map_table_name( $path->[-1] );

    my $from = join(", ", map { $self->_map_table_name( $_) } @ordered, $path->[-1] );

    print "\n**$from\n";
    
    my $sql = "SELECT $pathtable.visual_id FROM $from WHERE ". join(" and ", @where);
    print "ZOOM * * *  $sql\n";
    my $res = $self->{storage}->dosql_select( $sql, [] );
    
    foreach my $r ( @$res ) {
      my $name = "$self->{namespace}::$relative";
      my $obj = $name->new( $r->{visual_id} );
      $obj->{_pathlength} = scalar @$path - 1;
      
      $result{$r->{visual_id}} = $obj;

      print "ZOOM ---> [ID] = [$obj->{_id}]\n";
    }
  }

  return sort { $a->{_pathlength} <=> $b->{_pathlength} } values %result;
}

sub _relation_side {
  my $self = shift;
  my $table = shift;
  my $entity = shift;

  my( $e1, $e2 ) = split /_R_/, $table;

#  print "ZOOM --> is $entity first in $table?\n";

  if ($e1 eq $entity) {
#    print "ZOOM --> Yes\n";
    return 'lval';
  } else {
#    print "ZOOM --> No\n";

    return 'rval';
  }
}

sub _get_relation {
    my ($self, $e1, $e2) = @_;

    my $storage = $self->{storage};
    
    my $schemaref = $storage->fetch( "MetaRelation" => { return => 'relation',
							 where => { 'entity1' => $e1, 'entity2' => $e2 } } );
    my $schema = $schemaref->[0]->{relation};
    
    # Sigh, try it the other way around, we don't have operator support yet in the DB.
    unless ($schema) {
	$schemaref = $storage->fetch( "MetaRelation" => { return => 'relation',
							  where => { 'entity2' => $e1, 'entity1' => $e2 } } );
	$schema = $schemaref->[0]->{relation};
    }
    
    return $schema;
}

sub _fetch_related {
  my $self = shift;
  my $start = shift;
  my $stop = shift;
  my $path = [ @{ shift || [] } ];
  my $all = shift || [];

  my $storage = $self->{storage};

  return if grep { $_ eq $start } @$path;
  push( @$path, $start );

  return $path if $start eq $stop;

  foreach my $child ( $storage->get_relations($start) ) {
    my $found_path = $self->_fetch_related( $child, $stop, $path, $all );

    push( @$all, $found_path ) if $found_path;
  }

  return $all if @$path == 1;
}

sub _map_table_name {
    my $self = shift;
    
    $self->Yggdrasil::Storage::SQL::_map_table_name( @_ );
}

1;
