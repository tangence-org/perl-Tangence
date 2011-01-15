#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010 -- leonerd@leonerd.org.uk

package Tangence::Metacode;

use strict;
use warnings;

our $VERSION = '0.02';

use Carp;

use Tangence::Constants;

sub init_class
{
   my $class = shift;

   my $meta = $class->_meta;

   foreach my $superclass ( $meta->superclasses ) {
      init_class( $superclass ) unless defined &{"${superclass}::_has_Tangence"};
   }

   my %subs = (
      _has_Tangence => sub() { 1 },
   );

   my $props = $meta->can_property;

   foreach my $prop ( keys %$props ) {
      my $pdef = $props->{$prop};

      init_class_property( $class, $prop, $pdef, \%subs );
   }

   no strict 'refs';

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
      my $cbs = $self->{properties}->{$prop}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$prop}->[0] ) 
                       : $_->{on_set}->( $self, $newval ) for @$cbs;
   };

   my $dim = $pdef->{dim};

   my $dimname = DIMNAMES->[$dim];
   if( my $code = __PACKAGE__->can( "init_class_property_$dimname" ) ) {
      $code->( $class, $prop, $pdef, $subs );
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
      my $cbs = $self->{properties}->{$prop}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$prop}->[0] ) 
                       : $_->{on_add}->( $self, $key, $value ) for @$cbs;
   };

   $subs->{"del_prop_$prop"} = sub {
      my $self = shift;
      my ( $key ) = @_;
      delete $self->{properties}->{$prop}->[0]->{$key};
      my $cbs = $self->{properties}->{$prop}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$prop}->[0] ) 
                       : $_->{on_del}->( $self, $key ) for @$cbs;
   };
}

sub init_class_property_queue
{
   my ( $class, $prop, $pdef, $subs ) = @_;

   $subs->{"push_prop_$prop"} = sub {
      my $self = shift;
      my @values = @_;
      push @{ $self->{properties}->{$prop}->[0] }, @values;
      my $cbs = $self->{properties}->{$prop}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$prop}->[0] ) 
                       : $_->{on_push}->( $self, @values ) for @$cbs;
   };

   $subs->{"shift_prop_$prop"} = sub {
      my $self = shift;
      my ( $count ) = @_;
      $count = 1 unless @_;
      splice @{ $self->{properties}->{$prop}->[0] }, 0, $count, ();
      my $cbs = $self->{properties}->{$prop}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$prop}->[0] ) 
                       : $_->{on_shift}->( $self, $count ) for @$cbs;
   };
}

sub init_class_property_array
{
   my ( $class, $prop, $pdef, $subs ) = @_;

   $subs->{"push_prop_$prop"} = sub {
      my $self = shift;
      my @values = @_;
      push @{ $self->{properties}->{$prop}->[0] }, @values;
      my $cbs = $self->{properties}->{$prop}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$prop}->[0] ) 
                       : $_->{on_push}->( $self, @values ) for @$cbs;
   };

   $subs->{"shift_prop_$prop"} = sub {
      my $self = shift;
      my ( $count ) = @_;
      $count = 1 unless @_;
      splice @{ $self->{properties}->{$prop}->[0] }, 0, $count, ();
      my $cbs = $self->{properties}->{$prop}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$prop}->[0] ) 
                       : $_->{on_shift}->( $self, $count ) for @$cbs;
   };

   $subs->{"splice_prop_$prop"} = sub {
      my $self = shift;
      my ( $index, $count, @values ) = @_;
      splice @{ $self->{properties}->{$prop}->[0] }, $index, $count, @values;
      my $cbs = $self->{properties}->{$prop}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$prop}->[0] ) 
                       : $_->{on_splice}->( $self, $index, $count, @values ) for @$cbs;
   };

   $subs->{"move_prop_$prop"} = sub {
      my $self = shift;
      my ( $index, $delta ) = @_;
      return if $delta == 0;
      # it turns out that exchanging neighbours is quicker by list assignment,
      # but other times it's generally best to use splice() to extract then
      # insert
      my $cache = $self->{properties}->{$prop}->[0];
      if( abs($delta) == 1 ) {
         @{$cache}[$index,$index+$delta] = @{$cache}[$index+$delta,$index];
      }
      else {
         my $elem = splice @$cache, $index, 1, ();
         splice @$cache, $index + $delta, 0, ( $elem );
      }
      my $cbs = $self->{properties}->{$prop}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$prop}->[0] ) 
                       : $_->{on_move}->( $self, $index, $delta ) for @$cbs;
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
      my $cbs = $self->{properties}->{$prop}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$prop}->[0] ) 
                       : $_->{on_set}->( $self, [ values %$newval ] ) for @$cbs;
   };

   $subs->{"add_prop_$prop"} = sub {
      my $self = shift;
      my ( $obj ) = @_;
      $self->{properties}->{$prop}->[0]->{$obj->id} = $obj;
      my $cbs = $self->{properties}->{$prop}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$prop}->[0] ) 
                       : $_->{on_add}->( $self, $obj ) for @$cbs;
   };

   $subs->{"del_prop_$prop"} = sub {
      my $self = shift;
      my ( $obj_or_id ) = @_;
      my $id = ref $obj_or_id ? $obj_or_id->id : $obj_or_id;
      delete $self->{properties}->{$prop}->[0]->{$id};
      my $cbs = $self->{properties}->{$prop}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$prop}->[0] ) 
                       : $_->{on_del}->( $self, $id ) for @$cbs;
   };
}

# Keep perl happy; keep Britain tidy
1;

__END__

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>
