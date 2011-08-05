#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011 -- leonerd@leonerd.org.uk

package Tangence::Meta::Property;

use strict;
use warnings;
use base qw( Tangence::Compiler::Property );

our $VERSION = '0.07';

use Carp;

use Tangence::Constants;

sub build_subs
{
   my $self = shift;
   my ( $subs ) = @_;

   my $pname = $self->name;

   $subs->{"get_prop_$pname"} = sub {
      my $self = shift;
      return $self->{properties}->{$pname}->[0]
   };

   $subs->{"set_prop_$pname"} = sub {
      my $self = shift;
      my ( $newval ) = @_;
      $self->{properties}->{$pname}->[0] = $newval;
      my $cbs = $self->{properties}->{$pname}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$pname}->[0] ) 
                       : $_->{on_set}->( $self, $newval ) for @$cbs;
   };

   my $dim = $self->dimension;

   my $dimname = DIMNAMES->[$dim];
   if( my $code = __PACKAGE__->can( "_build_subs_for_$dimname" ) ) {
      $code->( $self, $subs, $pname );
   }
   else {
      croak "Unrecognised property dimension $dim for $pname";
   }
}

sub _build_subs_for_scalar
{
   # Nothing needed
}

sub _build_subs_for_hash
{
   my $self = shift;
   my ( $subs, $pname ) = @_;

   $subs->{"add_prop_$pname"} = sub {
      my $self = shift;
      my ( $key, $value ) = @_;
      $self->{properties}->{$pname}->[0]->{$key} = $value;
      my $cbs = $self->{properties}->{$pname}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$pname}->[0] ) 
                       : $_->{on_add}->( $self, $key, $value ) for @$cbs;
   };

   $subs->{"del_prop_$pname"} = sub {
      my $self = shift;
      my ( $key ) = @_;
      delete $self->{properties}->{$pname}->[0]->{$key};
      my $cbs = $self->{properties}->{$pname}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$pname}->[0] ) 
                       : $_->{on_del}->( $self, $key ) for @$cbs;
   };
}

sub _build_subs_for_queue
{
   my $self = shift;
   my ( $subs, $pname ) = @_;

   $subs->{"push_prop_$pname"} = sub {
      my $self = shift;
      my @values = @_;
      push @{ $self->{properties}->{$pname}->[0] }, @values;
      my $cbs = $self->{properties}->{$pname}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$pname}->[0] ) 
                       : $_->{on_push}->( $self, @values ) for @$cbs;
   };

   $subs->{"shift_prop_$pname"} = sub {
      my $self = shift;
      my ( $count ) = @_;
      $count = 1 unless @_;
      splice @{ $self->{properties}->{$pname}->[0] }, 0, $count, ();
      my $cbs = $self->{properties}->{$pname}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$pname}->[0] ) 
                       : $_->{on_shift}->( $self, $count ) for @$cbs;
   };
}

sub _build_subs_for_array
{
   my $self = shift;
   my ( $subs, $pname ) = @_;

   $subs->{"push_prop_$pname"} = sub {
      my $self = shift;
      my @values = @_;
      push @{ $self->{properties}->{$pname}->[0] }, @values;
      my $cbs = $self->{properties}->{$pname}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$pname}->[0] ) 
                       : $_->{on_push}->( $self, @values ) for @$cbs;
   };

   $subs->{"shift_prop_$pname"} = sub {
      my $self = shift;
      my ( $count ) = @_;
      $count = 1 unless @_;
      splice @{ $self->{properties}->{$pname}->[0] }, 0, $count, ();
      my $cbs = $self->{properties}->{$pname}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$pname}->[0] ) 
                       : $_->{on_shift}->( $self, $count ) for @$cbs;
   };

   $subs->{"splice_prop_$pname"} = sub {
      my $self = shift;
      my ( $index, $count, @values ) = @_;
      splice @{ $self->{properties}->{$pname}->[0] }, $index, $count, @values;
      my $cbs = $self->{properties}->{$pname}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$pname}->[0] ) 
                       : $_->{on_splice}->( $self, $index, $count, @values ) for @$cbs;
   };

   $subs->{"move_prop_$pname"} = sub {
      my $self = shift;
      my ( $index, $delta ) = @_;
      return if $delta == 0;
      # it turns out that exchanging neighbours is quicker by list assignment,
      # but other times it's generally best to use splice() to extract then
      # insert
      my $cache = $self->{properties}->{$pname}->[0];
      if( abs($delta) == 1 ) {
         @{$cache}[$index,$index+$delta] = @{$cache}[$index+$delta,$index];
      }
      else {
         my $elem = splice @$cache, $index, 1, ();
         splice @$cache, $index + $delta, 0, ( $elem );
      }
      my $cbs = $self->{properties}->{$pname}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$pname}->[0] ) 
                       : $_->{on_move}->( $self, $index, $delta ) for @$cbs;
   };
}

sub _build_subs_for_objset
{
   my $self = shift;
   my ( $subs, $pname ) = @_;

   # Different set method
   $subs->{"set_prop_$pname"} = sub {
      my $self = shift;
      my ( $newval ) = @_;
      $self->{properties}->{$pname}->[0] = $newval;
      my $cbs = $self->{properties}->{$pname}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$pname}->[0] ) 
                       : $_->{on_set}->( $self, [ values %$newval ] ) for @$cbs;
   };

   $subs->{"add_prop_$pname"} = sub {
      my $self = shift;
      my ( $obj ) = @_;
      $self->{properties}->{$pname}->[0]->{$obj->id} = $obj;
      my $cbs = $self->{properties}->{$pname}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$pname}->[0] ) 
                       : $_->{on_add}->( $self, $obj ) for @$cbs;
   };

   $subs->{"del_prop_$pname"} = sub {
      my $self = shift;
      my ( $obj_or_id ) = @_;
      my $id = ref $obj_or_id ? $obj_or_id->id : $obj_or_id;
      delete $self->{properties}->{$pname}->[0]->{$id};
      my $cbs = $self->{properties}->{$pname}->[1];
      $_->{on_updated} ? $_->{on_updated}->( $self, $self->{properties}->{$pname}->[0] ) 
                       : $_->{on_del}->( $self, $id ) for @$cbs;
   };
}

0x55AA;
