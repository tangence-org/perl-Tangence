#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010 -- leonerd@leonerd.org.uk

package Tangence::Meta::Class;

use strict;
use warnings;

our %metas; # cache one per class

sub new
{
   my $class = shift;
   my ( $name ) = @_;

   return $metas{$name} if exists $metas{$name};

   return $metas{$name} = bless {
      name => $name,
   }, $class;
}

sub superclasses
{
   my $self = shift;
   my ( $class ) = @_;

   $class ||= $self->{name};

   return do { no strict 'refs'; @{$class."::ISA"} };
}

sub supermetas
{
   my $self = shift;
   my ( $class ) = @_;

   return map { Tangence::Meta::Class->new( $_ ) } $self->superclasses;
}

sub can_method
{
   my $self = shift;
   my ( $method, $class ) = @_;

   $class ||= $self->{name};

   my %methods = do { no strict 'refs'; %{$class."::METHODS"} };

   return $methods{$method} if defined $method and exists $methods{$method};

   foreach my $supermeta ( $self->supermetas ) {
      my $m = $supermeta->can_method( $method );
      if( defined $method ) {
         return $m if $m;
      }
      else {
         exists $methods{$_} or $methods{$_} = $m->{$_} for keys %$m;
      }
   }

   return \%methods unless defined $method;
   return undef;
}

sub can_event
{
   my $self = shift;
   my ( $event, $class ) = @_;

   $class ||= $self->{name};

   my %events = do { no strict 'refs'; %{$class."::EVENTS"} };

   return $events{$event} if defined $event and exists $events{$event};

   foreach my $supermeta ( $self->supermetas ) {
      my $e = $supermeta->can_event( $event );
      if( defined $event ) {
         return $e if $e;
      }
      else {
         exists $events{$_} or $events{$_} = $e->{$_} for keys %$e;
      }
   }

   return \%events unless defined $event;
   return undef;
}

sub can_property
{
   my $self = shift;
   my ( $prop, $class ) = @_;

   $class ||= $self->{name};

   my %props = do { no strict 'refs'; %{$class."::PROPS"} };

   return $props{$prop} if defined $prop and exists $props{$prop};

   foreach my $supermeta ( $self->supermetas ) {
      my $p = $supermeta->can_property( $prop );
      if( defined $prop ) {
         return $p if $p;
      }
      else {
         exists $props{$_} or $props{$_} = $p->{$_} for keys %$p;
      }
   }

   return \%props unless defined $prop;
   return undef;
}

sub smashkeys
{
   my $self = shift;
   my ( $class ) = @_;

   $class ||= $self->{name};

   my %props = do { no strict 'refs'; %{$class."::PROPS"} };

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

   my $class = $self->{name};

   my $ret = {
      methods    => $self->can_method(),
      events     => $self->can_event(),
      properties => $self->can_property(),
      isa        => [ $class, $self->superclasses( $class ) ],
   };

   return $ret;
}

# Keep perl happy; keep Britain tidy
1;

__END__

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>
