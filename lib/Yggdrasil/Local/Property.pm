package Yggdrasil::Local::Property;

use strict;
use warnings;

use base qw/Yggdrasil::Property/;

sub define {
    my $class  = shift;
    my $self   = $class->SUPER::new(@_);
    my %params = @_;

    my $yggdrasil = $self->yggdrasil();
    my $storage   = $yggdrasil->storage();
    my $status    = $self->get_status();
    
    my $property_name = $params{property};
    my $entity_name;

    # Deal with possibly being passed objects.  However, the property
    # is the id of the thing we wish to define, it better *not* be an
    # object.
    if (ref $params{entity}) {
	$self->{entity} = $params{entity};
	$entity_name = $self->{entity}->_userland_id();
    } else {
	$self->{entity} = $yggdrasil->get_entity( $params{entity} );
	unless ($status->OK()) {
	    $status->set( 400, "Unknown entity '$entity_name' requested for property '$property_name'." );
	    return;
	}
	$entity_name = $params{entity};
    }
    
    unless (length $property_name) {
	$status->set( 400, "Unable to create properties with zero length names." );
	return;
    }
    
    # Input types:
    # $ygg->define_property( Foo::Bar::Baz:prop )
    # $baz_entity->define_property( prop );
    
    # Auth passes MetaAuthUser request as a MetaAuth object, hackish.
    # This catches requests on the form MetaAuthRole:password and similar constructs.
    if ($entity_name) {
	if( $property_name =~ /:/ ) {
	    $status->set( 406, "Unable to create properties with names containing ':'." );
	    return;
	}
    } elsif( $property_name =~ /:/ ) {
	my @parts = split m/::/, $property_name;
	my $last = pop @parts;
	($entity_name, $property_name) = (split m/:/, $last, 2);
	push( @parts, $entity_name );
	$entity_name = join('::', @parts);
	$self->{entity} = $yggdrasil->get_entity( $entity_name );
	unless( $status->OK() ) {
	    $status->set( 400, "Unknown entity '$entity_name' requested for property '$property_name'." );
	    return;
	}
    } else {
	# we have no entity and the property name contains no ":"
	# This means we were called as $ygg->define_property( "foo" );
	# that makes no sense!
	$status->set( 406, "Unable to determine correct entity for the property requested " );
	return;
    }
    
    my $name = join(":", $entity_name, $property_name);

    $self->{name}   = $property_name;

    # --- Set the default data type.
    $params{type}   = uc $params{type} if $params{type};
    $params{type} ||= 'TEXT';
    $params{nullp}  = 1 if $params{nullp} || ! defined $params{nullp};

    unless ($storage->is_valid_type( $params{type} )) {
	my $ptype = $params{type};
	$status->set( 400, "Unknown property type '$ptype' requested for property '$property_name'." );
	return;
    }
    
    # --- Create Property table
    $storage->define( $name,
		      fields   => { id    => { type => "INTEGER" },
				    value => { type => $params{type},
					       null => $params{nullp}}},
		      
		      temporal => 1,
		      hints => {
				id => { index => 1, foreign => 'Instances', key => 1 },
				value => { index => 1 },
			       },
		      authschema => 1,
		      auth => {			       
			       create => [
					  'Instances:Auth' => {
							       where => [
									 id => \q<id>,
									 'm' => 1,
									],
							      }
					 ],
			       fetch => [ 
					 ':Auth' => {
						     where => [
							       id => \qq<$name.id>,
							       r  => 1,
							      ],
						    },
					],
			       expire => [
					  ':Auth' => {
						      where => [
								id  => \qq<$name.id>,
								'm' => 1,
							       ],
						     },
					 ],
			       update => [ 
					  ':Auth' => { 
						      where => [
								id => \qq<$name.id>,
								w  => 1,
							       ],
						     },
					 ],
			      },
		    );
    
    # --- Add to MetaProperty
    # Why isn't this in Y::MetaProperty?
    if ($status->status() == 202) {
	$status->set( 202, "Property '$property_name' already exists with the requested structure for entity '$entity_name'" )
    } elsif ($status->status() >= 400 ) {
	$status->set( 202, "Property '$property_name' already exists for '$entity_name', unable to create with requested parameters" );
    } else {
	$storage->store("MetaProperty", key => [qw/entity property/],
			fields => { entity   => $self->entity()->_internal_id(),
				    property => $property_name,
				    type     => $params{type},
				    nullp    => $params{nullp},
				  } ) unless $params{raw};
	$status->set( 201, "Property '$property_name' created for '$entity_name'." );
    }

    return $self;
}

sub objectify {
    my %params = @_;
    
    my $obj = new Yggdrasil::Local::Property( name      => $params{name},
					      entity    => $params{entity},
					      yggdrasil => $params{yggdrasil} );
    $obj->{name}       = $params{name};
    $obj->{entity}     = $params{entity};
    $obj->{_id}        = $params{id};
    $obj->{_start}     = $params{start};
    $obj->{_stop}      = $params{stop};
    $obj->{_realstart} = $params{realstart};
    $obj->{_realstop}  = $params{realstop};
    return $obj;
}

sub get {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    my %params = @_;    
    
    my $status = $self->get_status();
    my ($entityobj, $entity, $propname);

    my $time = $params{time} || {};

    if ($params{entity}) {
	$propname = $params{property};
    } else {
	my @parts = split m/::/, $params{property};
	my $last = pop @parts;
	($entity, $propname) = (split m/:/, $last, 2);
	push( @parts, $entity );
	$params{entity} = join('::', @parts);
    }

    if (ref $params{entity}) {
	$entityobj = $params{entity}; 
    } else {
	$entityobj = $self->yggdrasil()->get_entity( $params{entity}, time => $time );
    }

    # property_exists does not require the entity to actually exist
    # for the test to be valid, so there's no reason to ask storage to
    # create a proper entity object above, hence we use objectify and
    # then call propert_exists on that object directly.
    my $prop = $entityobj->property_exists( $propname );
    if ($prop) {
	$self->{name}       = $propname;
	$self->{entity}     = $entityobj;
	$self->{_id}        = $prop->{id};
	$self->{_realstart} = $prop->{start};
	$self->{_realstop}  = $prop->{stop};
	$self->{_start}     = $time->{start} || $prop->{start};
	$self->{_stop}      = $time->{stop} || $prop->{stop};
	$status->set( 200 );
	return $self;
    } else {
	$status->set( 404 );
	return undef;
    }
}

sub expire {
    my $self = shift;
    my $storage = $self->storage();

    my $status = $self->get_status();

    # Can't expire historic object
    if( $self->stop() ) {
	$status->set( 406, "Unable to expire properties in historic context" );
	return;
    }

    # You might not have permission to do this, can fails now either way.
    my $can = $storage->can( create => "MetaProperty", { entity => $self->entity()->_internal_id() } );

    return unless $can;

    $storage->expire( $self->entity()->_userland_id() . ':' . $self->_userland_id() );
    return unless $status->OK();

    $storage->expire( 'MetaProperty', id => $self->{_id} );
    return 1 if $status->OK();
    return;
}

# _get_meta returns meta data for a property, information about nullp
# and type is currently supported.
sub _get_meta {
    my ($self, $meta) = (shift, shift);
    my %params = @_;
    my $property = $self->{name};

    my $status = $self->get_status();

    my $time = $self->_validate_temporal( $params{time} );
    return unless $time;

    unless ($meta eq 'null' || $meta eq 'type') {
	$status->set( 406, "$meta is not a valid metadata request" );
	return undef;
    }

    # The internal name for the null field is "nullp".
    # FIX: why cant null() send 'nullp' as param instead of 'null' and void this test?
    $meta = 'nullp' if $meta eq 'null';

    my $entity = $self->entity();
    my $storage = $self->storage();
    my @ancestors = $entity->ancestors( $time );

    foreach my $e ( @ancestors ) {
	my $ret = $storage->fetch('MetaEntity', { where => [ entity => $e ] },
				  'MetaProperty',{ return => $meta,
						   where  => [ entity   => \qq{MetaEntity.id},
							       property => $property ]},
				  $time );
	
	next unless @$ret;
	return $ret->[0]->{$meta};
    }
}

1;

