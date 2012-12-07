#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010-2011 -- leonerd@leonerd.org.uk

package Tangence::Class;

use strict;
use warnings;
use base qw( Tangence::Meta::Class );

use Tangence::Constants;

use Tangence::Meta::Method;
use Tangence::Meta::Event;
use Tangence::Meta::Property;
use Tangence::Meta::Argument;

use Carp;

BEGIN {
   if( eval { require Sub::Name } ) {
      Sub::Name->import(qw( subname ));
   }
   else {
      # Emulate it by just returning the CODEref and ignoring setting the name
      *subname = sub { $_[1] };
   }
}

our $VERSION = '0.11';

our %metas; # cache one per class, keyed by _Tangence_ class name

# It would be really useful to put this in List::Utils or somesuch
sub pairmap(&@)
{
   my $code = shift;
   return map { $code->( local $a = shift, local $b = shift ) } 0 .. @_/2-1;
}

sub new
{
   my $class = shift;
   my %args = @_;
   my $name = $args{name};

   return $metas{$name} ||= $class->SUPER::new( @_ );
}

sub declare
{
   my $class = shift;
   my ( $perlname, %args ) = @_;

   ( my $name = $perlname ) =~ s{::}{.}g;

   my $self;
   if( exists $metas{$name} ) {
      $self = $metas{$name};
      local $metas{$name};

      my $newself = $class->new( name => $name );

      %$self = %$newself;
   }
   else {
      $self = $class->new( name => $name );
   }

   my %methods;
   foreach ( keys %{ $args{methods} } ) {
      $methods{$_} = Tangence::Meta::Method->new(
         name => $_,
         %{ $args{methods}{$_} },
         arguments => [ map {
            Tangence::Meta::Argument->new( name => $_->[0], type => $_->[1] )
         } @{ $args{methods}{$_}{args} } ],
      );
   }

   my %events;
   foreach ( keys %{ $args{events} } ) {
      $events{$_} = Tangence::Meta::Event->new(
         name => $_,
         %{ $args{events}{$_} },
         arguments => [ map {
            Tangence::Meta::Argument->new( name => $_->[0], type => $_->[1] )
         } @{ $args{events}{$_}{args} } ],
      );
   }

   my %properties;
   foreach ( keys %{ $args{props} } ) {
      $properties{$_} = Tangence::Meta::Property->new(
         name => $_,
         %{ $args{props}{$_} },
         dimension => $args{props}{$_}{dim} || DIM_SCALAR,
      );
   }

   $self->define(
      methods    => \%methods,
      events     => \%events,
      properties => \%properties,
   );
}

sub define
{
   my $self = shift;
   $self->SUPER::define( @_ );

   my $class = $self->perlname;

   my %subs;

   foreach my $prop ( values %{ $self->direct_properties } ) {
      $self->build_accessor( $prop, \%subs );
   }

   no strict 'refs';
   foreach my $name ( keys %subs ) {
      next if defined &{"${class}::${name}"};
      *{"${class}::${name}"} = subname "${class}::${name}" => $subs{$name};
   }
}

sub for_perlname
{
   my $class = shift;
   my ( $perlname ) = @_;

   ( my $name = $perlname ) =~ s{::}{.}g;
   return $metas{$name} or croak "Unknown Tangence::Class for '$perlname'";
}

sub perlname
{
   my $self = shift;
   ( my $perlname = $self->name ) =~ s{\.}{::}g; # s///rg in 5.14
   return $perlname;
}

sub superclasses
{
   my $self = shift;

   my @supers = $self->SUPER::superclasses;

   if( !@supers and $self->perlname ne "Tangence::Object" ) {
      @supers = Tangence::Class->for_perlname( "Tangence::Object" );
   }

   return @supers;
}

sub method
{
   my $self = shift;
   my ( $name ) = @_;
   return $self->methods->{$name};
}

sub event
{
   my $self = shift;
   my ( $name ) = @_;
   return $self->events->{$name};
}

sub property
{
   my $self = shift;
   my ( $name ) = @_;
   return $self->properties->{$name};
}

sub smashkeys
{
   my $self = shift;
   my %smash;
   $smash{$_->name} = 1 for grep { $_->smashed } values %{ $self->properties };
   return \%smash;
}

sub introspect
{
   my $self = shift;

   my $ret = {
      methods    => { 
         pairmap {
            $a => { args => [ $b->argtypes ], ret => $b->ret || "" }
         } %{ $self->methods }
      },
      events     => {
         pairmap {
            $a => { args => [ $b->argtypes ] }
         } %{ $self->events }
      },
      properties => {
         pairmap {
            $a => { type => $b->type, dim => $b->dimension, $b->smashed ? ( smash => 1 ) : () }
         } %{ $self->properties }
      },
      isa        => [
         grep { $_ ne "Tangence::Object" } $self->perlname, map { $_->perlname } $self->superclasses
      ],
   };

   return $ret;
}

sub build_accessor
{
   my $self = shift;
   my ( $prop, $subs ) = @_;

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

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
