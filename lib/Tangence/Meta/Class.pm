#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010-2011 -- leonerd@leonerd.org.uk

package Tangence::Meta::Class;

use strict;
use warnings;

use Carp;

our $VERSION = '0.06';

our %metas; # cache one per class

sub new
{
   my $class = shift;
   my ( $name, %args ) = @_;

   return $metas{$name} if exists $metas{$name};

   my $self = $metas{$name} = bless {
      name => $name,
   }, $class;

   no strict 'refs';
   no warnings 'once'; # In case these vars are not defined

   $self->{superclasses} = [ @{"$self->{name}::ISA"}     ];

   $self->{methods}      = $args{methods} || {};
   $self->{events}       = $args{events}  || {};
   $self->{props}        = $args{props}   || {};

   return $self;
}

sub declare
{
   my $class = shift;
   my ( $name ) = @_;

   if( exists $metas{$name} ) {
      my $oldself = $metas{$name};
      local $metas{$name};

      my $newself = $class->new( @_ );

      %$oldself = %$newself;
   }
   else {
      $class->new( @_ );
   }
}

sub for_perlname
{
   shift;
   my ( $perlname ) = @_;
   return $metas{$perlname} or croak "Unknown Tangence::Meta::Class for '$perlname'";
}

sub superclasses
{
   my $self = shift;
   return @{ $self->{superclasses} };
}

sub supermetas
{
   my $self = shift;
   my @supers = $self->superclasses;
   # If I have no superclasses, then use Tangence::Object instead
   @supers = "Tangence::Object" if !@supers and $self->{name} ne "Tangence::Object";
   return map { Tangence::Meta::Class->for_perlname( $_ ) } @supers;
}

sub methods
{
   my $self = shift;

   my %methods = %{ $self->{methods} };

   foreach my $supermeta ( $self->supermetas ) {
      my $m = $supermeta->methods;
      exists $methods{$_} or $methods{$_} = $m->{$_} for keys %$m;
   }

   return \%methods;
}

sub method
{
   my $self = shift;
   my ( $name ) = @_;
   return $self->methods->{$name};
}

sub events
{
   my $self = shift;

   my %events = %{ $self->{events} };

   foreach my $supermeta ( $self->supermetas ) {
      my $e = $supermeta->events;
      exists $events{$_} or $events{$_} = $e->{$_} for keys %$e;
   }

   return \%events;
}

sub event
{
   my $self = shift;
   my ( $name ) = @_;
   return $self->events->{$name};
}

sub properties
{
   my $self = shift;

   my %props = %{ $self->{props} };

   foreach my $supermeta ( $self->supermetas ) {
      my $p = $supermeta->properties;
      exists $props{$_} or $props{$_} = $p->{$_} for keys %$p;
   }

   return \%props;
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

   my %props = %{ $self->{props} };

   my %smash;

   $props{$_}->{smash} and $smash{$_} = 1 for keys %props;

   foreach my $supermeta ( $self->supermetas ) {
      my $supkeys = $supermeta->smashkeys;

      # Merge keys we don't yet have
      $smash{$_} = 1 for keys %$supkeys;
   }

   return \%smash;
}

sub introspect
{
   my $self = shift;

   my $ret = {
      methods    => $self->methods,
      events     => $self->events,
      properties => $self->properties,
      isa        => [ $self->{name}, $self->superclasses ],
   };

   return $ret;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
