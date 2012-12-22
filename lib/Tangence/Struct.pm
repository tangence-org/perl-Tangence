package Tangence::Struct;

use strict;
use warnings;

use Carp;

our %structta;

sub new
{
   my $class = shift;
   my %args = @_;
   my $name = $args{name};

   return $structta{$name} ||= bless {
      name   => $name,
      fields => $args{fields}
   }, $class;
}

sub _new_type
{
   my ( $sig ) = @_;
   require Tangence::Meta::Type;
   return Tangence::Meta::Type->new_from_sig( $sig );
}

sub declare
{
   my $class = shift;
   my ( $perlname, %args ) = @_;

   require Tangence::Meta::Argument;

   ( my $name = $perlname ) =~ s{::}{.}g;

   my @fields;
   my @fieldnames;
   for( $_ = 0; $_ < @{$args{fields}}; $_ += 2 ) {
      push @fields, Tangence::Meta::Argument->new(
         name => $args{fields}[$_],
         type => Tangence::Meta::Type->new_from_sig( $args{fields}[$_+1] ),
      );
      push @fieldnames, $args{fields}[$_];
   }

   my $struct = $class->new(
      name => $name,
      fields => \@fields,
   );

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
   defined *{"${perlname}::$_"} or *{"${perlname}::$_"} = $subs{$_} for keys %subs;

   return $struct;
}

sub for_perlname
{
   my $class = shift;
   my ( $perlname ) = @_;

   ( my $name = $perlname ) =~ s{::}{.}g;
   return $structta{$name} or croak "Unknown Tangence::Struct for '$perlname'";
}

sub name
{
   my $self = shift;
   return $self->{name};
}

sub perlname
{
   my $self = shift;
   ( my $perlname = $self->name ) =~ s{\.}{::}g; # s///rg in 5.14
   return $perlname;
}

sub fields
{
   my $self = shift;
   return @{ $self->{fields} };
}

0x55AA;
