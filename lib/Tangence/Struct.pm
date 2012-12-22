package Tangence::Struct;

use strict;
use warnings;
use base qw( Tangence::Meta::Struct );

use Carp;

use Tangence::Meta::Field;

our %structs;

sub new
{
   my $class = shift;
   my %args = @_;
   my $name = $args{name};

   return $structs{$name} ||= $class->SUPER::new( @_ );
}

sub _new_type
{
   my ( $sig ) = @_;
   return Tangence::Meta::Type->new_from_sig( $sig );
}

sub declare
{
   my $class = shift;
   my ( $perlname, %args ) = @_;

   ( my $name = $perlname ) =~ s{::}{.}g;

   my @fields;
   for( $_ = 0; $_ < @{$args{fields}}; $_ += 2 ) {
      push @fields, Tangence::Meta::Field->new(
         name => $args{fields}[$_],
         type => Tangence::Meta::Type->new_from_sig( $args{fields}[$_+1] ),
      );
   }

   my $self = $class->new( name => $name );

   $self->define(
      fields => \@fields,
   );

   return $self;
}

sub define
{
   my $self = shift;
   $self->SUPER::define( @_ );

   my $class = $self->perlname;
   my @fieldnames = map { $_->name } $self->fields;

   # Now construct the actual perl package
   my %subs = (
      new => sub {
         my $class = shift;
         my %args = @_;
         exists $args{$_} or croak "$class is missing $_" for @fieldnames;
         bless [ @args{@fieldnames} ], $class;
      },
   );
   $subs{$fieldnames[$_]} = do { my $i = $_; sub { shift->[$i] } } for 0 .. $#fieldnames;

   no strict 'refs';
   foreach my $name ( keys %subs ) {
      next if defined &{"${class}::${name}"};
      *{"${class}::${name}"} = $subs{$name};
   }
}

sub for_perlname
{
   my $class = shift;
   my ( $perlname ) = @_;

   ( my $name = $perlname ) =~ s{::}{.}g;
   return $structs{$name} or croak "Unknown Tangence::Struct for '$perlname'";
}

sub perlname
{
   my $self = shift;
   ( my $perlname = $self->name ) =~ s{\.}{::}g; # s///rg in 5.14
   return $perlname;
}

0x55AA;
