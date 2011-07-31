#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010-2011 -- leonerd@leonerd.org.uk

package Tangence::Meta::Class;

use strict;
use warnings;
use base qw( Tangence::Compiler::Class );

use Tangence::Constants;

use Tangence::Compiler::Method;
use Tangence::Compiler::Event;
use Tangence::Compiler::Property;
use Tangence::Compiler::Argument;

use Carp;

our $VERSION = '0.07';

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
      $methods{$_} = Tangence::Compiler::Method->new(
         name => $_,
         %{ $args{methods}{$_} },
         arguments => [ map {
            Tangence::Compiler::Argument->new( name => $_->[0], type => $_->[1] )
         } @{ $args{methods}{$_}{args} } ],
      );
   }

   my %events;
   foreach ( keys %{ $args{events} } ) {
      $events{$_} = Tangence::Compiler::Event->new(
         name => $_,
         %{ $args{events}{$_} },
         arguments => [ map {
            Tangence::Compiler::Argument->new( name => $_->[0], type => $_->[1] )
         } @{ $args{events}{$_}{args} } ],
      );
   }

   my %properties;
   foreach ( keys %{ $args{props} } ) {
      $properties{$_} = Tangence::Compiler::Property->new(
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

sub for_perlname
{
   my $class = shift;
   my ( $perlname ) = @_;

   ( my $name = $perlname ) =~ s{::}{.}g;
   return $metas{$name} or croak "Unknown Tangence::Meta::Class for '$perlname'";
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
      @supers = Tangence::Meta::Class->for_perlname( "Tangence::Object" );
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

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
