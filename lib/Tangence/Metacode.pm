package Tangence::Metacode;

use strict;

use Carp;

use Tangence::Constants;

sub init_class
{
   my $class = shift;

   # This method does lots of evilness. But we'll try to keep it brief, and
   # all in one place
   no strict 'refs';

   foreach my $superclass ( @{$class."::ISA"} ) {
      init_class( $superclass ) unless defined &{"${superclass}::_has_Tangence"};
   }

   my %subs = (
      _has_Tangence => sub() { 1 },
   );

   my %props = %{$class."::PROPS"};

   foreach my $prop ( keys %props ) {
      my $pdef = $props{$prop};

      init_class_property( $class, $prop, $pdef, \%subs );
   }

   foreach my $name ( keys %subs ) {
      next if defined &{"${class}::${name}"};
      *{"${class}::${name}"} = $subs{$name};
   }
}

sub init_class_property
{
   my ( $class, $prop, $pdef, $subs ) = @_;

   $subs->{"get_prop_$prop"} = sub {
      my $self = shift;
      return $self->{properties}->{$prop}->[0]
   };

   $subs->{"set_prop_$prop"} = sub {
      my $self = shift;
      my ( $newval ) = @_;
      $self->{properties}->{$prop}->[0] = $newval;
      $self->update_property( $prop, CHANGE_SET, $newval );
   };

   my $dim = $pdef->{dim};

   if( $dim == DIM_SCALAR ) {
      init_class_property_scalar( $class, $prop, $pdef, $subs );
   }
   elsif( $dim == DIM_HASH ) {
      init_class_property_hash( $class, $prop, $pdef, $subs );
   }
   elsif( $dim == DIM_ARRAY ) {
      init_class_property_array( $class, $prop, $pdef, $subs );
   }
   elsif( $dim == DIM_OBJSET ) {
      init_class_property_objset( $class, $prop, $pdef, $subs );
   }
   else {
      croak "Unrecognised property dimension $dim for $class :: $prop";
   }
}

sub init_class_property_scalar
{
   my ( $class, $prop, $pdef, $subs ) = @_;

   # Nothing needed
}

sub init_class_property_hash
{
   my ( $class, $prop, $pdef, $subs ) = @_;

   $subs->{"add_prop_$prop"} = sub {
      my $self = shift;
      my ( $key, $value ) = @_;
      $self->{properties}->{$prop}->[0]->{$key} = $value;
      $self->update_property( $prop, CHANGE_ADD, $key, $value );
   };

   $subs->{"del_prop_$prop"} = sub {
      my $self = shift;
      my ( $key ) = @_;
      delete $self->{properties}->{$prop}->[0]->{$key};
      $self->update_property( $prop, CHANGE_DEL, $key );
   };
}

sub init_class_property_array
{
   my ( $class, $prop, $pdef, $subs ) = @_;

   $subs->{"push_prop_$prop"} = sub {
      my $self = shift;
      my @values = @_;
      push @{ $self->{properties}->{$prop}->[0] }, @values;
      $self->update_property( $prop, CHANGE_PUSH, @values );
   };

   $subs->{"shift_prop_$prop"} = sub {
      my $self = shift;
      my ( $count ) = @_;
      $count = 1 unless @_;
      splice @{ $self->{properties}->{$prop}->[0] }, 0, $count, ();
      $self->update_property( $prop, CHANGE_SHIFT, $count );
   };

   $subs->{"splice_prop_$prop"} = sub {
      my $self = shift;
      my ( $index, $count, @values ) = @_;
      splice @{ $self->{properties}->{$prop}->[0] }, $index, $count, @values;
      $self->update_property( $prop, CHANGE_SPLICE, $index, $count, @values );
   };
}

sub init_class_property_objset
{
   my ( $class, $prop, $pdef, $subs ) = @_;

   # Different set method
   $subs->{"set_prop_$prop"} = sub {
      my $self = shift;
      my ( $newval ) = @_;
      $self->{properties}->{$prop}->[0] = $newval;
      $self->update_property( $prop, CHANGE_SET, [ values %$newval ] );
   };

   $subs->{"add_prop_$prop"} = sub {
      my $self = shift;
      my ( $obj ) = @_;
      $self->{properties}->{$prop}->[0]->{$obj->id} = $obj;
      $self->update_property( $prop, CHANGE_ADD, $obj );
   };

   $subs->{"del_prop_$prop"} = sub {
      my $self = shift;
      my ( $obj_or_id ) = @_;
      my $id = ref $obj_or_id ? $obj_or_id->id : $obj_or_id;
      delete $self->{properties}->{$prop}->[0]->{$id};
      $self->update_property( $prop, CHANGE_DEL, $id );
   };
}

1;
