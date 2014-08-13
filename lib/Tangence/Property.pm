#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2013 -- leonerd@leonerd.org.uk

package Tangence::Property;

use strict;
use warnings;
use base qw( Tangence::Meta::Property );

use Carp;

use Tangence::Constants;

require Tangence::Type;

our $VERSION = '0.20';

sub build_accessor
{
   my $prop = shift;
   my ( $subs ) = @_;

   my $pname = $prop->name;

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

   my $dim = $prop->dimension;

   my $dimname = DIMNAMES->[$dim];
   if( my $code = __PACKAGE__->can( "_accessor_for_$dimname" ) ) {
      $code->( $prop, $subs, $pname );
   }
   else {
      croak "Unrecognised property dimension $dim for $pname";
   }
}

sub _accessor_for_scalar
{
   # Nothing needed
}

sub _accessor_for_hash
{
   my $prop = shift;
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

sub _accessor_for_queue
{
   my $prop = shift;
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
      my $iters = $self->{properties}->{$pname}->[2];
      $_->idx -= $count for @$iters;
   };

   $subs->{"iter_prop_$pname"} = sub {
      my $self = shift;
      my ( $iter_from ) = @_;
      my $idx = $iter_from == ITER_FIRST ? 0 :
                $iter_from == ITER_LAST  ? scalar @{ $self->{properties}->{$pname}->[0] } :
                                           die "Unrecognised iter_from";
      my $iters = $self->{properties}->{$pname}->[2] ||= [];
      push @$iters, my $iter = Tangence::Property::_Iterator->new( $self->{properties}->{$pname}->[0], $prop, $idx );
      return $iter;
   };
}

sub _accessor_for_array
{
   my $prop = shift;
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

sub _accessor_for_objset
{
   my $prop = shift;
   my ( $subs, $pname ) = @_;

   # Different get and set methods
   $subs->{"get_prop_$pname"} = sub {
      my $self = shift;
      return [ values %{ $self->{properties}->{$pname}->[0] } ];
   };

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

sub make_type
{
   shift;
   return Tangence::Type->new( @_ );
}

package # hide from CPAN
   Tangence::Property::_Iterator;

use Carp;

use Tangence::Constants;

sub new
{
   my $class = shift;
   return bless [ @_ ], $class;
}

sub queue { shift->[0] }
sub prop  { shift->[1] }
sub idx :lvalue { shift->[2] }

sub handle_request_ITER_NEXT
{
   my $self = shift;
   my ( $ctx, $message ) = @_;

   my $direction = $message->unpack_int();
   my $count     = $message->unpack_int();

   my $queue = $self->queue;
   my $idx   = $self->idx;

   if( $direction == ITER_FWD ) {
      $count = scalar @$queue - $idx if $count > scalar @$queue - $idx;

      $self->idx += $count;
   }
   elsif( $direction == ITER_BACK ) {
      $count = $idx if $count > $idx;
      $idx -= $count;

      $self->idx -= $count;
   }
   else {
      return $ctx->responderr( "Unrecognised iterator direction $direction" );
   }

   my @result = @{$queue}[$idx .. $idx + $count - 1];

   $ctx->respond( Tangence::Message->new( $ctx->stream, MSG_ITER_RESULT )
      ->pack_int( $idx )
      ->pack_all_sametype( $self->prop->type, @result )
   );
}

0x55AA;
