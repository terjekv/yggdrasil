package Yggdrasil::Local::Relation;

use strict;
use warnings;

use base qw/Yggdrasil::Relation/;

sub define {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    my %param   = @_;

    my ($lval, $rval) = @{$param{entities}};
  
    my $storage = $self->{yggdrasil}->{storage};
    
    $lval = $lval->{name} if $lval->{name};
    $rval = $rval->{name} if $rval->{name};
    
    my $label = defined $param{label} ? $param{label} : "$lval<->$rval";
    $self->{label} = $label;
    
    $lval = Yggdrasil::Local::Entity->get( yggdrasil => $self, entity => $lval );
    $rval = Yggdrasil::Local::Entity->get( yggdrasil => $self, entity => $rval );;

    $self->{lval} = $lval;
    $self->{rval} = $rval;

    unless( $param{raw} ) {
	my $relation = __PACKAGE__->get( yggdrasil => $self, label => $label );
	return $relation if $relation;
    }

    # --- Add to MetaRelation
    my $id = Yggdrasil::MetaRelation->add( yggdrasil => $self, 
					   lval      => $lval->{_id},
					   rval      => $rval->{_id},
					   label     => $label) unless $param{raw};
    #my $id = $self->_meta_add($lval, $rval, $label, %param) unless $param{raw};
    $self->{_id} = $id;
    return $self;
}

sub get {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    my %param = @_; 
    
    my $status = $param{yggdrasil}->get_status();
    my $ref = $self->storage()->fetch( "MetaRelation" => { return => [qw/id lval rval start stop/],
							   where  => [ 'label' => $param{label} ] },
				     );

    if( $ref && defined $ref->[0]->{id} ) {
	my $new = Yggdrasil::Local::Relation->new( @_ );
	$new->{_id} = $ref->[0]->{id};
	$new->{_start} = $ref->[0]->{start};
	$new->{_stop}  = $ref->[0]->{stop};
	
	$new->{lval} = Yggdrasil::Local::Entity->get( yggdrasil => $self, id => $ref->[0]->{lval} );
	$new->{rval} = Yggdrasil::Local::Entity->get( yggdrasil => $self, id => $ref->[0]->{rval} );

	$new->{label} = $param{label};

	$status->set( 200 );
	return $new;
    } else {
	$status->set( 404 );
	return undef;	
    }    
}

sub get_all {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);

    my $aref = $self->{storage}->fetch( 'MetaRelation', { return => [ 'rval', 'lval', 'label' ] });

    return map { $_->{label} } @$aref;
    
}

sub id {
    my $self = shift;    
    return $self->{_id};
}

sub _get_real_val {
    my $self  = shift;
    my $side  = shift;
    my $label = shift;

    my $retref = $self->storage()->fetch( 'MetaEntity', { return => 'entity',
							  where  => [ id => \qq<MetaRelation.$side> ]},
					  'MetaRelation', { where => [ label => $label ]});
    return $retref->[0]->{entity};
}

sub participants {
    my $self = shift;
    
    my $storage = $self->storage();
    
    my $le = $self->{lval};
    my $re = $self->{rval};

    my $parts = $storage->fetch(
				Relations => {
					      return => ['relationid', 'lval', 'rval'],
					      where  => [ relationid => $self->{_id} ] },
			       );

    my @participants;
    foreach my $part (@$parts) {
	my $l = $part->{lval};
	my $r = $part->{rval};
	my $lval = $storage->fetch( Instances => { where => [ id => $l ],
						  return => 'visual_id' } );
	my $rval = $storage->fetch( Instances => { where => [ id => $r ],
						  return => 'visual_id' } );
	
	my $li = Yggdrasil::Local::Instance->new( yggdrasil => $self );
	$li->{visual_id} = $lval->[0]->{visual_id};
	$li->{_id}       = $l;
	$li->{entity}    = $le;

	my $ri = Yggdrasil::Local::Instance->new( yggdrasil => $self );
	$ri->{visual_id} = $rval->[0]->{visual_id};
	$ri->{_id}       = $r;
	$ri->{entity}    = $re;

	push( @participants, [ $li, $ri ] );
    }

    return @participants;
}

sub entities {
    my $self = shift;

    return ( $self->{lval}, $self->{rval} );
}

sub label {
    my $self = shift;

    return $self->{label};
}

sub link :method {
  my $self = shift;
  my $lval = shift;
  my $rval = shift;

  my $label = $self->{label};

  my $reallval = $self->_get_real_val( 'lval', $label );
  my $realrval = $self->_get_real_val( 'rval', $label );

  my $status = $self->get_status();

  unless ($lval && ref $lval && ref $lval eq 'Yggdrasil::Local::Instance') {
      $status->set( 406, "The first paramter to link has to be an instance object." );
      return undef;      
  }

  unless ($rval && ref $rval && ref $rval eq 'Yggdrasil::Local::Instance') {
      $status->set( 406, "The second paramter to link has to be an instance object." );
      return undef;      
  }
  
  unless ($lval->is_a( $reallval )) {
      $status->set( 406, $lval->id() . " cannot use the relation $label, incompatible instance / inheritance." );
      return undef;
  }

  unless ($rval->is_a( $realrval )) {
      $status->set( 406, $rval->id() . " cannot use the relation $label, incompatible instance / inheritance." );
      return undef;
  }

  $self->storage()->store( 'Relations',
			   key => ['relationid', 'lval', 'rval' ],
			   fields => {
			       'relationid' => $self->id(),
			       'lval' => $lval->{_id},
			       'rval' => $rval->{_id} });
}

sub unlink :method {
  my $self = shift;
  my $lval = shift;
  my $rval = shift;

  $self->storage()->expire( 'Relations', lval => $lval->{_id}, rval => $rval->{_id} );
}


sub _admin_dump {
    my $self = shift;
    my $id   = shift;

    return $self->{storage}->raw_fetch( Relations => { where => [ relationid => $id ] } );
}

sub _admin_restore {
    my $self  = shift;
    my $data  = shift;

    $self->{storage}->raw_store( 'Relations', fields => $data );
}

1;